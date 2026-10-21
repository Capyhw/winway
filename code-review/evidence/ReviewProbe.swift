import AppKit
import WinwayCore

@main struct ReviewProbe {
 @MainActor static func main() throws {
  func log(_ value: String) { print(value); fflush(nil) }
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root = URL(fileURLWithPath: "/tmp/winway-review-probe")
  let model = AppModel(directory: root, settingsURL: root.appendingPathComponent("settings.json"))
  model.controller = ExplorerWindowController { _ in }
  model.tabs[0].entries = (0..<10_000).map { index in let i = (index * 7919) % 10000; return FileEntry(url: root.appendingPathComponent(String(format:"file-%05d",i)), name: String(format:"file-%05d",i), isDirectory: true) }
  model.controller.window?.contentView?.layoutSubtreeIfNeeded()
  for i in 0..<3 {
   let start = CFAbsoluteTimeGetCurrent()
   model.handle(.select([model.tabs[0].entries[i].url]))
   log("SELECT_10000_RUN_\(i)_MS=\((CFAbsoluteTimeGetCurrent()-start)*1000)")
  }
  let controller = model.controller!
  controller.window?.setContentSize(NSSize(width:960,height:600))
  controller.window?.contentView?.layoutSubtreeIfNeeded()
  model.render()
  let table = controller.fileTable
  log("NARROW_WINDOW=\(controller.window!.contentView!.bounds),TABLE_VIEWPORT=\(table.enclosingScrollView!.frame),COLUMNS=\(table.tableColumns.map { $0.width })")
  // Isolate editor geometry from selection timing.
  model.tabs[0].selection = [model.tabs[0].entries.last!.url]
  model.render()
  table.moveColumn(0,toColumn:3)
  model.render()
  controller.beginRename()
  func views(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(views) }
  guard let editor=views(controller.window!.contentView!).first(where: { $0.accessibilityIdentifier()=="winway.rename-editor" }) else { log("NO_REORDER_EDITOR selection=\(table.selectedRowIndexes)"); return }
  log("REORDER_COLUMN_IDS=\(table.tableColumns.map { $0.identifier.rawValue }),EDITOR=\(editor.frame),NAME_CELL=\(editor.superview!.convert(table.frameOfCell(atColumn:3,row:table.selectedRow),from:table))")
  let second = ExplorerWindowController { _ in }
  second.window?.setContentSize(NSSize(width:960,height:600))
  second.window?.contentView?.layoutSubtreeIfNeeded()
  var snap = ExplorerSnapshot()
  let entry = FileEntry(url: root.appendingPathComponent("One.txt"), name: "One.txt", isDirectory:false)
  snap.entries = [entry]; snap.selection = [entry.url]; snap.enabledCommands = Set(CommandID.allCases)
  second.render(snap)
  // Same-tab navigation resets the model offset but render ignores it.
  snap.entries = (0..<200).map { FileEntry(url:root.appendingPathComponent("a-\($0)"),name:"a-\($0)",isDirectory:false) }
  snap.selection = []
  second.render(snap)
  let clip = second.fileTable.enclosingScrollView!.contentView
  clip.scroll(to:NSPoint(x:0,y:1500))
  snap.directory = root.appendingPathComponent("B")
  snap.entries = (0..<200).map { FileEntry(url:snap.directory.appendingPathComponent("b-\($0)"),name:"b-\($0)",isDirectory:false) }
  snap.scrollOffset = 0
  second.render(snap)
  log("SAME_TAB_NAV_EXPECTED_OFFSET=0,ACTUAL=\(clip.bounds.origin.y + clip.contentInsets.top)")
  snap.entries=[entry]; snap.selection=[entry.url]
  second.render(snap)
  second.beginRename()
  let scroll=second.fileTable.enclosingScrollView!
  scroll.contentView.scroll(to:NSPoint(x:300,y:scroll.contentView.bounds.origin.y))
  scroll.reflectScrolledClipView(scroll.contentView)
  NotificationCenter.default.post(name:NSView.boundsDidChangeNotification,object:scroll.contentView)
  guard let editor2=views(second.window!.contentView!).first(where: { $0.accessibilityIdentifier()=="winway.rename-editor" }) else { log("NO_SCROLL_EDITOR"); return }
  log("HORIZONTAL_EDITOR=\(editor2.frame),LIST_VIEWPORT=\(scroll.frame),HIDDEN=\(editor2.isHidden)")
 }
}
