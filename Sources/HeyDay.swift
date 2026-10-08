import AppKit
import SwiftUI

// MARK: - Models

struct HeyEvent: Identifiable, Hashable {
  /// Stable per-day key: a repeating series shares `targetId` across days.
  let id: String
  /// The id `hey event edit/delete` acts on: own id if realized, else the series id.
  let targetId: Int64
  /// Set only for a virtual occurrence of a series (no recording of its own yet).
  let occurrence: String?
  let recurring: Bool
  var title: String
  var startMin: Int
  var durMin: Int
  let allDay: Bool
  /// False when the event crosses midnight — a day-view drag can't express that.
  let editable: Bool
  let calendar: String
}

struct HeyTodo: Identifiable, Hashable {
  let id: Int64
  let title: String
  var done: Bool
}

struct CalendarRef: Identifiable, Hashable {
  let id: Int64
  let name: String
}

struct Draft: Equatable {
  var startMin: Int
  var durMin: Int
}

// MARK: - hey CLI

enum Hey {
  static let path: String = {
    let candidates = [
      ProcessInfo.processInfo.environment["HEY_PATH"],
      "\(NSHomeDirectory())/go/bin/hey",
      "/opt/homebrew/bin/hey",
      "/usr/local/bin/hey",
    ].compactMap { $0 }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "hey"
  }()

  static func run(_ args: [String]) async throws -> Any {
    try await withCheckedThrowingContinuation { cont in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: path)
      p.arguments = args + ["--json"]
      let out = Pipe()
      p.standardOutput = out
      p.standardError = Pipe()
      p.terminationHandler = { _ in
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          return cont.resume(throwing: HeyError("bad output from hey \(args.joined(separator: " "))"))
        }
        if obj["ok"] as? Bool == false {
          let hint = (obj["hint"] as? String).map { " — \($0)" } ?? ""
          return cont.resume(throwing: HeyError((obj["error"] as? String ?? "hey failed") + hint))
        }
        cont.resume(returning: obj["data"] ?? NSNull())
      }
      do { try p.run() } catch { cont.resume(throwing: error) }
    }
  }

  static func parseDate(_ s: Any?) -> Date? {
    guard let s = s as? String else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
  }

  static func day(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }

  static func clock(_ m: Int) -> String {
    let m = min(m, 1439)
    return String(format: "%02d:%02d", m / 60, m % 60)
  }

  /// hey's own default zone reaches HEY as UTC, shifting every write by the UTC offset.
  static var zone: String {
    let z = UserDefaults.standard.string(forKey: "timeZone") ?? ""
    return z.isEmpty ? TimeZone.current.identifier : z
  }

  static func calendars() async throws -> [CalendarRef] {
    let cals = (try await run(["calendar", "list"]) as? [[String: Any]]) ?? []
    return cals.compactMap { c in
      guard let id = int64(c["id"]), c["kind"] as? String == "normal",
        c["external"] as? Bool != true
      else { return nil }
      return CalendarRef(id: id, name: c["name"] as? String ?? "Calendar \(id)")
    }
  }

  static func int64(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

  static func fetchEvents(_ date: Date) async throws -> [HeyEvent] {
    let dayStart = Calendar.current.startOfDay(for: date)
    let rows = (try await run(["event", "day", day(date), "--all"]) as? [[String: Any]]) ?? []
    return rows.compactMap { r in
      guard let id = int64(r["id"]), let s = parseDate(r["starts_at"]) else { return nil }
      let e = parseDate(r["ends_at"]) ?? s.addingTimeInterval(3600)
      let startMin = Int(s.timeIntervalSince(dayStart) / 60)
      let endMin = Int(e.timeIntervalSince(dayStart) / 60)
      let realized = int64(r["recording_id"]) != nil
      let occ = r["occurrence_id"] as? String
      let recurring = r["recurring"] as? Bool ?? (int64(r["parent_id"]) != nil)
      return HeyEvent(
        id: occ ?? "\(id)",
        targetId: id,
        occurrence: (recurring && !realized) ? occ : nil,
        recurring: recurring,
        title: r["title"] as? String ?? "(untitled)",
        startMin: max(0, startMin),
        durMin: max(15, min(1440, endMin) - max(0, startMin)),
        allDay: r["all_day"] as? Bool ?? false,
        editable: startMin >= 0 && endMin <= 1440,
        calendar: (r["calendar"] as? [String: Any])?["name"] as? String ?? "")
    }
  }

  /// The owned "Personal" calendar; `event add` without --calendar files to "Maybe".
  static func personalCalendar() async throws -> Int64? {
    let cals = (try await run(["calendar", "list"]) as? [[String: Any]]) ?? []
    let normal = cals.filter { $0["kind"] as? String == "normal" && $0["external"] as? Bool != true }
    let pick =
      normal.first { ($0["name"] as? String)?.lowercased() == "personal" }
      ?? normal.first { $0["owned"] as? Bool == true }
    return int64(pick?["id"])
  }

  static func fetchTodos(_ date: Date) async throws -> [HeyTodo] {
    let d = day(date)
    let rows =
      (try await run(["todo", "list", "--all", "--starts-on", d, "--ends-on", d]) as? [[String: Any]])
      ?? []
    return rows.compactMap { r in
      guard let id = int64(r["id"]) else { return nil }
      return HeyTodo(id: id, title: r["title"] as? String ?? "", done: r["completed_at"] is String)
    }
  }
}

struct HeyError: LocalizedError {
  let msg: String
  init(_ m: String) { msg = m }
  var errorDescription: String? { msg }
}

// MARK: - Store

@MainActor
final class DayStore: ObservableObject {
  @Published var date = Date()
  @Published var events: [HeyEvent] = []
  @Published var todos: [HeyTodo] = []
  @Published var draft: Draft?
  @Published var error: String?
  @Published var busy = 0
  /// True from a day switch until that day's first fetch lands.
  @Published var loading = true
  @Published var now = DayStore.demo ? DayStore.demoNow() : Date()
  @Published var calendars: [CalendarRef] = []
  private var cache: [String: (events: [HeyEvent], todos: [HeyTodo])] = [:]
  private var personalId: Int64?
  private var lastRefresh = Date.distantPast

  /// Settings override; 0 means the auto-detected Personal calendar.
  var targetCalendar: Int64? {
    let chosen = Int64(UserDefaults.standard.integer(forKey: "calendarId"))
    return chosen != 0 ? chosen : personalId
  }
  var defaultDuration: Int {
    let d = UserDefaults.standard.integer(forKey: "defaultDuration")
    return d == 0 ? 30 : d
  }

  init() {
    Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.shift(0) }
    }
    Task {
      personalId = try? await Hey.personalCalendar()
      calendars = (try? await Hey.calendars()) ?? []
      await refresh()
    }
  }

  /// Cheap refresh on hover so HEY-side deletes show up before the next poll.
  func refreshIfStale() {
    if Date().timeIntervalSince(lastRefresh) > 5 { Task { await refresh() } }
  }

  var key: String { Hey.day(date) }
  var isToday: Bool { Calendar.current.isDateInToday(date) }

  private func tick() {
    let wasToday = Calendar.current.isDate(now, inSameDayAs: date)
    now = Self.demo ? Self.demoNow() : Date()
    if wasToday && !isToday { shift(0) }
  }

  func shift(_ days: Int) {
    date = days == 0 ? Date() : Calendar.current.date(byAdding: .day, value: days, to: date)!
    let hit = cache[key]
    events = hit?.events ?? []
    todos = hit?.todos ?? []
    draft = nil
    loading = hit == nil
    Task { await refresh() }
  }

  private var writing = 0

  func refresh(force: Bool = false) async {
    if writing > 0 && !force { return }
    if Self.demo {
      events = Self.demoEvents()
      now = Self.demoNow()
      loading = false
      return
    }
    lastRefresh = Date()
    busy += 1
    defer { busy -= 1 }
    let target = date
    do {
      async let e = Hey.fetchEvents(target)
      async let t = Hey.fetchTodos(target)
      let (ev, td) = try await (e, t)
      guard Calendar.current.isDate(target, inSameDayAs: date) else { return }
      events = ev
      todos = td
      cache[Hey.day(target)] = (ev, td)
      error = nil
      loading = false
      prefetchNeighbors(of: target)
    } catch {
      self.error = error.localizedDescription
      if Calendar.current.isDate(target, inSameDayAs: date) { loading = false }
    }
  }

  static let demo = ProcessInfo.processInfo.environment["HEYDAY_DEMO"] != nil
  static func demoNow() -> Date {
    Calendar.current.date(bySettingHour: 11, minute: 20, second: 0, of: Date())!
  }

  /// Sample day with the clock pinned to 11:20, for screenshots (`HEYDAY_DEMO=1`).
  static func demoEvents() -> [HeyEvent] {
    let h = 11 * 60
    func ev(_ i: Int, _ t: String, _ s: Int, _ d: Int, _ cal: String, rec: Bool = false, allDay: Bool = false)
      -> HeyEvent
    {
      HeyEvent(
        id: "demo\(i)", targetId: Int64(i), occurrence: nil, recurring: rec, title: t,
        startMin: max(0, min(1380, s)), durMin: d, allDay: allDay, editable: true, calendar: cal)
    }
    return [
      ev(0, "Product launch week", 0, 1440, "Work", allDay: true),
      ev(1, "Morning run", h - 180, 45, "Personal", rec: true),
      ev(2, "Standup", h - 90, 15, "Work", rec: true),
      ev(3, "Deep work: onboarding flow", h - 30, 90, "Focus"),
      ev(4, "Lunch", h + 90, 60, "Personal"),
      ev(5, "Design review", h + 180, 60, "Work"),
      ev(6, "1:1 with Sam", h + 210, 30, "Team"),
      ev(7, "Write launch post", h + 300, 75, "Focus"),
    ]
  }

  private func prefetchNeighbors(of day: Date) {
    for offset in [-1, 1] {
      let d = Calendar.current.date(byAdding: .day, value: offset, to: day)!
      let k = Hey.day(d)
      guard cache[k] == nil else { continue }
      Task {
        async let e = Hey.fetchEvents(d)
        async let t = Hey.fetchTodos(d)
        if let (ev, td) = try? await (e, t), cache[k] == nil { cache[k] = (ev, td) }
      }
    }
  }

  /// Runs a write, then re-reads the day so ids/occurrences match HEY.
  private func write(_ args: [String]) {
    writing += 1
    Task {
      busy += 1
      defer { busy -= 1 }
      do {
        _ = try await Hey.run(args)
      } catch {
        self.error = error.localizedDescription
      }
      writing -= 1
      await refresh(force: true)
    }
  }

  func create(_ title: String, at startMin: Int, duration: Int) {
    let t = title.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return }
    let s = max(0, min(startMin, 1440 - duration))
    events.append(
      HeyEvent(
        id: "pending-\(UUID())", targetId: 0, occurrence: nil, recurring: false, title: t,
        startMin: s, durMin: duration, allDay: false, editable: false, calendar: "saving…"))
    let args = [
      "event", "add", t, "--starts-on", key,
      "--start-time", Hey.clock(s), "--end-time", Hey.clock(s + duration), "--time-zone", Hey.zone,
    ]
    Task {
      if personalId == nil { personalId = try? await Hey.personalCalendar() }
      write(args + (targetCalendar.map { ["--calendar", "\($0)"] } ?? []))
    }
  }

  private func editArgs(_ e: HeyEvent) -> [String] {
    var a = ["event", "edit", "\(e.targetId)", key]
    if let occ = e.occurrence {
      a += ["--occurrence", occ, "--apply-to", "current", "--allow-plain-notes"]
    }
    return a
  }

  func retime(_ e: HeyEvent, start: Int, duration: Int) {
    guard e.editable, start != e.startMin || duration != e.durMin,
      let i = events.firstIndex(of: e)
    else { return }
    events[i].startMin = start
    events[i].durMin = duration
    write(
      editArgs(e) + [
        "--starts-on", key, "--start-time", Hey.clock(start),
        "--end-time", Hey.clock(start + duration), "--time-zone", Hey.zone,
      ])
  }

  func rename(_ e: HeyEvent, to title: String) {
    let t = title.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, t != e.title, let i = events.firstIndex(of: e) else { return }
    events[i].title = t
    write(editArgs(e) + ["--title", t])
  }

  /// A virtual occurrence has no id of its own; deleting its target would kill the series.
  func canDelete(_ e: HeyEvent) -> Bool { e.occurrence == nil && !e.id.hasPrefix("pending") }

  func delete(_ e: HeyEvent) {
    guard canDelete(e) else { return }
    events.removeAll { $0.id == e.id }
    write(["event", "delete", "\(e.targetId)"])
  }

  func addTodo(_ title: String) {
    write(["todo", "add", "--title", title, "--date", key])
  }

  func toggle(_ todo: HeyTodo) {
    guard let i = todos.firstIndex(of: todo) else { return }
    todos[i].done.toggle()
    write(["todo", todo.done ? "uncomplete" : "complete", "\(todo.id)"])
  }

  /// "Deep work 90m" / "Lunch 1h" / "Call 1:30pm 45m" -> (title, start, duration)
  func parseQuick(_ raw: String) -> (String, Int?, Int) {
    var words = raw.split(separator: " ").map(String.init)
    var duration = 30
    var start: Int?
    words.removeAll { w in
      let l = w.lowercased()
      if let m = l.wholeMatch(of: /(\d+(?:\.\d+)?)(m|min|h|hr)/) {
        let n = Double(m.1) ?? 0
        duration = Int(m.2.hasPrefix("h") ? n * 60 : n)
        return true
      }
      if let m = l.wholeMatch(of: /@?(\d{1,2})(?::(\d{2}))?(am|pm)?/), m.3 != nil || m.2 != nil {
        var h = Int(m.1) ?? 0
        if m.3 == "pm" && h < 12 { h += 12 }
        if m.3 == "am" && h == 12 { h = 0 }
        start = h * 60 + (m.2.flatMap { Int($0) } ?? 0)
        return true
      }
      return false
    }
    return (words.joined(separator: " "), start, max(15, duration))
  }

  var nextSlot: Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
    return isToday ? ((c.hour! * 60 + c.minute!) / 15 + 1) * 15 : 9 * 60
  }
}

// MARK: - Views

let snap = 15
func snapped(_ m: Double) -> Int { Int((m / Double(snap)).rounded()) * snap }
func hhmm(_ m: Int) -> String {
  let h = (m / 60) % 24
  return String(format: "%d:%02d%@", h % 12 == 0 ? 12 : h % 12, m % 60, h < 12 ? "a" : "p")
}
func hue(_ s: String) -> Double {
  let palette = [0.58, 0.08, 0.36, 0.78, 0.95, 0.15, 0.5]
  return palette[abs(s.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % palette.count]
}

struct RootView: View {
  @ObservedObject var store: DayStore
  @AppStorage("hourHeight") private var hourHeight: Double = 52
  @State private var hovering = false

  var body: some View {
    VStack(spacing: 0) {
      header
      allDayStrip
      Timeline(store: store, hourHeight: hourHeight)
        .opacity(store.loading ? 0.4 : 1)
        .overlay {
          if store.loading {
            ProgressView().controlSize(.small)
          }
        }
        .animation(.easeOut(duration: 0.15), value: store.loading)
    }
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onHover { h in
      hovering = h
      if h { store.refreshIfStale() }
    }
  }

  var header: some View {
    HStack(spacing: 10) {
      Text(store.date.formatted(.dateTime.weekday(.abbreviated).day()))
        .font(.system(size: 13, weight: .semibold, design: .rounded))
      if !store.isToday {
        Button { store.shift(0) } label: {
          Text("Today").font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
      }
      if store.loading || store.busy > 0 {
        ProgressView().controlSize(.mini).scaleEffect(0.8)
      }
      if let e = store.error {
        Circle().fill(.red).frame(width: 6, height: 6)
          .help(e)
          .onTapGesture { store.error = nil }
      }
      Spacer()
      if hovering {
        Group {
          Button { store.shift(-1) } label: { Image(systemName: "chevron.left") }
          Button { store.shift(1) } label: { Image(systemName: "chevron.right") }
          Button { (NSApp.delegate as? AppDelegate)?.openSettings() } label: {
            Image(systemName: "gearshape")
          }
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
      }
    }
    .padding(.horizontal, 12).frame(height: 30)
    .background(WindowDragArea())
  }

  @ViewBuilder var allDayStrip: some View {
    let allDay = store.events.filter(\.allDay)
    if !allDay.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(allDay) { e in
            Text(e.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
              .padding(.horizontal, 6).padding(.vertical, 3)
              .background(Capsule().fill(Color(hue: hue(e.calendar), saturation: 0.5, brightness: 0.8).opacity(0.35)))
          }
        }.padding(.horizontal, 10)
      }.padding(.bottom, 6)
    }
  }

}

struct Timeline: View {
  @ObservedObject var store: DayStore
  let hourHeight: Double
  @State private var sketch: (start: Int, end: Int)?
  @AppStorage("startHour") private var startHourRaw = 0
  @AppStorage("endHour") private var endHourRaw = 24
  var startHour: Int { min(max(0, startHourRaw), 23) }
  var endHour: Int { max(startHour + 1, min(24, endHourRaw)) }
  var ppm: Double { hourHeight / 60 }
  let gutter: CGFloat = 40

  var nowMin: Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: store.now)
    return c.hour! * 60 + c.minute!
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        ZStack(alignment: .topLeading) {
          grid
          GeometryReader { geo in
            let width = geo.size.width - gutter - 8
            ZStack(alignment: .topLeading) {
              createLayer
              ForEach(layout(width: width), id: \.event.id) { slot in
                EventView(event: slot.event, ppm: ppm, store: store)
                  .frame(width: slot.width - 2, height: max(16, Double(slot.event.durMin) * ppm - 2))
                  .offset(x: gutter + slot.x, y: Double(slot.event.startMin) * ppm + 1)
              }
              if let d = store.draft {
                DraftView(draft: d, store: store)
                  .frame(width: width, height: max(22, Double(d.durMin) * ppm))
                  .offset(x: gutter, y: Double(d.startMin) * ppm)
              }
              if let s = sketch {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.3))
                  .overlay(alignment: .topLeading) {
                    Text("\(hhmm(min(s.start, s.end))) – \(hhmm(max(s.start, s.end)))")
                      .font(.system(size: 10, weight: .medium)).padding(4)
                  }
                  .frame(width: width, height: Double(abs(s.end - s.start)) * ppm)
                  .offset(x: gutter, y: Double(min(s.start, s.end)) * ppm)
                  .allowsHitTesting(false)
              }
              if store.isToday { nowLine(width: geo.size.width) }
            }
          }
        }
        .frame(height: 24 * hourHeight)
        .offset(y: -Double(startHour) * hourHeight)
        .frame(
          height: Double(endHour - startHour) * hourHeight + (endHour < 24 ? 8 : 0),
          alignment: .top)
        .padding(.top, startHour == 0 ? 0 : 8)
        .clipped()
        .padding(.top, startHour == 0 ? 8 : 0)
        .padding(.bottom, 8)
      }
      .onAppear { scrollToNow(proxy) }
      .onChange(of: store.date) { _ in scrollToNow(proxy) }
      .onChange(of: startHourRaw) { _ in scrollToNow(proxy) }
    }
  }

  func scrollToNow(_ proxy: ScrollViewProxy) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      let h = store.isToday ? nowMin / 60 - 2 : 8
      proxy.scrollTo(min(max(startHour, h), endHour - 1), anchor: .top)
    }
  }

  var grid: some View {
    VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { h in
        HStack(alignment: .top, spacing: 6) {
          let current = store.isToday && h == nowMin / 60
          Text(h == 0 ? "" : hhmm(h * 60).replacingOccurrences(of: ":00", with: ""))
            .font(.system(size: 11, weight: current ? .bold : .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary.opacity(current ? 1 : 0.7))
            .frame(width: gutter - 6, alignment: .trailing)
            .offset(y: -7)
          VStack(spacing: 0) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            Spacer()
            Rectangle().fill(.primary.opacity(0.035)).frame(height: 1)
            Spacer()
          }
        }
        .frame(height: hourHeight, alignment: .top)
        .opacity(store.isToday && h < nowMin / 60 ? 0.5 : 1)
        .id(h)
      }
    }
  }

  /// Drag on empty space to sketch an event; double-click for a 30m one.
  var createLayer: some View {
    Color.clear.contentShape(Rectangle())
      .padding(.leading, gutter)
      .gesture(
        DragGesture(minimumDistance: 4)
          .onChanged { v in
            sketch = (snapped(v.startLocation.y / ppm), snapped(v.location.y / ppm))
          }
          .onEnded { _ in
            guard let s = sketch else { return }
            sketch = nil
            store.draft = Draft(startMin: min(s.start, s.end), durMin: max(snap, abs(s.end - s.start)))
          }
      )
      .simultaneousGesture(
        SpatialTapGesture(count: 2).onEnded { v in
          store.draft = Draft(
            startMin: Int(v.location.y / ppm) / 30 * 30, durMin: store.defaultDuration)
        })
  }

  func nowLine(width: CGFloat) -> some View {
    HStack(spacing: 0) {
      Text(hhmm(nowMin)).font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(.white).padding(.horizontal, 3).padding(.vertical, 1)
        .background(Capsule().fill(.red))
        .frame(width: gutter, alignment: .trailing)
      Circle().fill(.red).frame(width: 7, height: 7).offset(x: -3)
      Rectangle().fill(.red).frame(height: 1.5)
    }
    .frame(width: width)
    .offset(y: Double(nowMin) * ppm - 7)
    .shadow(color: .red.opacity(0.5), radius: 3)
    .allowsHitTesting(false)
  }

  struct Slot {
    let event: HeyEvent
    var x: CGFloat = 0
    var width: CGFloat = 0
  }

  /// Greedy column layout so overlapping events sit side by side.
  func layout(width: CGFloat) -> [Slot] {
    let timed = store.events.filter { !$0.allDay }
      .sorted { ($0.startMin, -$0.durMin) < ($1.startMin, -$1.durMin) }
    var result: [Slot] = []
    var cluster: [(HeyEvent, Int)] = []
    var clusterEnd = -1
    var colEnds: [Int] = []
    func flush() {
      let cols = (cluster.map(\.1).max() ?? 0) + 1
      for (e, c) in cluster {
        let w = width / CGFloat(cols)
        result.append(Slot(event: e, x: CGFloat(c) * w, width: w))
      }
      cluster = []
      colEnds = []
    }
    for e in timed {
      if e.startMin >= clusterEnd { flush() }
      let col = colEnds.firstIndex { $0 <= e.startMin } ?? colEnds.count
      if col == colEnds.count { colEnds.append(0) }
      colEnds[col] = e.startMin + e.durMin
      cluster.append((e, col))
      clusterEnd = max(clusterEnd, e.startMin + e.durMin)
    }
    flush()
    return result
  }
}

struct DraftView: View {
  let draft: Draft
  @ObservedObject var store: DayStore
  @State private var title = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      TextField("New event", text: $title).textFieldStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .focused($focused)
        .onSubmit {
          store.create(title, at: draft.startMin, duration: draft.durMin)
          store.draft = nil
        }
        .onExitCommand { store.draft = nil }
      Text("\(hhmm(draft.startMin)) – \(hhmm(draft.startMin + draft.durMin))")
        .font(.system(size: 9)).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 6).padding(.vertical, 3)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.35)))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1))
    .onAppear { focusWidget { focused = true } }
  }
}

struct EventView: View {
  let event: HeyEvent
  let ppm: Double
  @ObservedObject var store: DayStore

  @State private var moveDelta: Double = 0
  @State private var resizeDelta: Double = 0
  @State private var editing = false
  @State private var title = ""
  @FocusState private var focused: Bool

  var liveStart: Int {
    max(0, min(1440 - event.durMin, event.startMin + snapped(moveDelta / ppm)))
  }
  var liveDur: Int {
    max(snap, min(1440 - event.startMin, event.durMin + snapped(resizeDelta / ppm)))
  }
  var color: Color { Color(hue: hue(event.calendar), saturation: 0.55, brightness: 0.85) }
  var dragging: Bool { moveDelta != 0 || resizeDelta != 0 }
  var past: Bool { store.isToday && event.startMin + event.durMin <= nowMin }
  var current: Bool {
    store.isToday && event.startMin <= nowMin && nowMin < event.startMin + event.durMin
  }
  var nowMin: Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: store.now)
    return c.hour! * 60 + c.minute!
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      if editing {
        TextField("", text: $title).textFieldStyle(.plain)
          .font(.system(size: 11, weight: .semibold))
          .focused($focused)
          .onSubmit(commit)
          .onExitCommand { editing = false }
      } else {
        HStack(spacing: 3) {
          if event.recurring {
            Image(systemName: "repeat").font(.system(size: 8)).foregroundStyle(.secondary)
          }
          Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
        }
      }
      Text("\(hhmm(liveStart)) – \(hhmm(liveStart + liveDur))")
        .font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
    }
    .padding(.horizontal, 6).padding(.vertical, 3)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 6).fill(color.opacity(dragging ? 0.55 : current ? 0.5 : 0.3))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: current ? 4 : 3) }
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
      if current {
        RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 1.5)
      }
    }
    .shadow(color: color.opacity(current && !dragging ? 0.45 : 0), radius: 5)
    .overlay(alignment: .bottom) { if event.editable { resizeHandle } }
    .opacity(past && !dragging ? 0.55 : 1)
    .offset(y: moveDelta)
    .padding(.bottom, -resizeDelta)
    .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 6, y: 3)
    .zIndex(dragging ? 1 : 0)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { if event.editable { startEdit() } }
    .gesture(
      DragGesture(minimumDistance: 3)
        .onChanged { if event.editable { moveDelta = $0.translation.height } }
        .onEnded { _ in
          let s = liveStart
          moveDelta = 0
          store.retime(event, start: s, duration: event.durMin)
        }
    )
    .contextMenu {
      if event.editable { Button("Rename", action: startEdit) }
      if event.occurrence != nil {
        Text("Repeating — edits change this day only")
      }
      Divider()
      Button("Delete", role: .destructive) { store.delete(event) }
        .disabled(!store.canDelete(event))
    }
  }

  var resizeHandle: some View {
    Capsule().fill(color.opacity(0.9)).frame(width: 24, height: 3)
      .frame(maxWidth: .infinity).frame(height: 8)
      .contentShape(Rectangle())
      .onHover { inside in inside ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
      .highPriorityGesture(
        DragGesture(minimumDistance: 1)
          .onChanged { resizeDelta = $0.translation.height }
          .onEnded { _ in
            let d = liveDur
            resizeDelta = 0
            store.retime(event, start: event.startMin, duration: d)
          }
      )
  }

  func startEdit() {
    title = event.title
    editing = true
    focusWidget { focused = true }
  }

  func commit() {
    editing = false
    store.rename(event, to: title)
  }
}

struct SettingsView: View {
  @ObservedObject var store: DayStore
  var onTopChanged: (Bool) -> Void
  @AppStorage("calendarId") private var calendarId = 0
  @AppStorage("timeZone") private var timeZone = ""
  @AppStorage("defaultDuration") private var duration = 30
  @AppStorage("hourHeight") private var hourHeight: Double = 52
  @AppStorage("onTop") private var onTop = false
  @AppStorage("startHour") private var startHour = 0
  @AppStorage("endHour") private var endHour = 24

  var body: some View {
    Form {
      Picker("New events go to", selection: $calendarId) {
        Text("Personal (auto)").tag(0)
        ForEach(store.calendars) { Text($0.name).tag(Int($0.id)) }
      }
      Picker("Time zone", selection: $timeZone) {
        Text("System (\(TimeZone.current.identifier))").tag("")
        Divider()
        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
      }
      Picker("Double-click length", selection: $duration) {
        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
      }
      Picker("Day starts", selection: $startHour) {
        ForEach(0..<24, id: \.self) { Text(hhmm($0 * 60)).tag($0) }
      }
      .onChange(of: startHour) { s in if endHour <= s { endHour = s + 1 } }
      Picker("Day ends", selection: $endHour) {
        ForEach(1...24, id: \.self) { Text($0 == 24 ? "midnight" : hhmm($0 * 60)).tag($0) }
      }
      .onChange(of: endHour) { e in if startHour >= e { startHour = e - 1 } }
      LabeledContent("Hour height") {
        Slider(value: $hourHeight, in: 28...120)
      }
      Toggle("Float above windows", isOn: $onTop)
        .onChange(of: onTop, perform: onTopChanged)
    }
    .formStyle(.grouped)
    .frame(width: 400)
    .fixedSize()
  }
}

/// A desktop-level window only takes typing once the app is active and it is key.
func focusWidget(_ then: @escaping () -> Void) {
  NSApp.activate(ignoringOtherApps: true)
  NSApp.windows.first { $0 is DesktopWindow }?.makeKey()
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: then)
}

/// Lets the header move the borderless window.
struct WindowDragArea: NSViewRepresentable {
  final class V: NSView {
    override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
  }
  func makeNSView(context: Context) -> NSView { V() }
  func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: - App

final class DesktopWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: DesktopWindow!
  var status: NSStatusItem!
  var store: DayStore!
  var settings: NSWindow?
  var onTop = UserDefaults.standard.bool(forKey: "onTop")

  func applicationDidFinishLaunching(_ n: Notification) {
    store = DayStore()
    window = DesktopWindow(
      contentRect: NSRect(x: 60, y: 120, width: 340, height: 640),
      styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.minSize = NSSize(width: 240, height: 320)
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.contentView = NSHostingView(rootView: RootView(store: store))
    window.setFrameAutosaveName("HeyDayWindow")
    applyLevel()
    window.orderFrontRegardless()
    if let out = ProcessInfo.processInfo.environment["HEYDAY_SNAPSHOT"] {
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
        let v = window.contentView!
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2), pixelsHigh: Int(v.bounds.height * 2),
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = v.bounds.size
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        NSApp.terminate(nil)
      }
    }

    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.image = NSImage(
      systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: "HeyDay")
    let menu = NSMenu()
    menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r")
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
    status.menu = menu
  }

  func applyLevel() {
    window.level =
      onTop ? .floating : NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
  }

  @objc func refresh() { Task { await store.refresh() } }

  @objc func openSettings() {
    if settings == nil {
      let w = NSWindow(
        contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      w.title = "HeyDay Settings"
      w.isReleasedWhenClosed = false
      w.contentView = NSHostingView(
        rootView: SettingsView(store: store) { [weak self] top in
          self?.onTop = top
          self?.applyLevel()
        })
      w.center()
      settings = w
    }
    NSApp.activate(ignoringOtherApps: true)
    settings?.level = .floating
    settings?.makeKeyAndOrderFront(nil)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
