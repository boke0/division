import AppKit
import DivisionKit
import SwiftUI

struct SwitcherItem: Identifiable {
    var id: WindowID
    var number: Int
    var title: String
    var appName: String
    /// 1-based pane label when this window is assigned; `nil` when unassigned.
    var pane: Int?
    var isAssigned: Bool
    var icon: NSImage?
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var session = SwitcherSession(count: 0)
    @Published var paneIndex = 0

    func reload(from engine: TilingEngine, pane: Int) {
        let previousID = highlightedID
        paneIndex = pane
        let windows = engine.switcherWindows(in: pane)
        items = windows.enumerated().map { index, window in
            let title = window.title.isEmpty ? window.appName : window.title
            let assignedPane = engine.paneIndex(for: window.id)
            return SwitcherItem(
                id: window.id,
                number: index + 1,
                title: title,
                appName: window.appName,
                pane: assignedPane.map { $0 + 1 },
                isAssigned: assignedPane == pane,
                icon: NSRunningApplication(processIdentifier: window.pid)?.icon
            )
        }
        session.updateCount(items.count)
        if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            session.preferHighlight(index)
        }
    }

    func resetInput() {
        session = SwitcherSession(count: items.count)
    }

    func appendDigit(_ character: Character) {
        session.appendDigit(character)
    }

    func deleteLastDigit() {
        session.deleteLastDigit()
    }

    func moveHighlight(by offset: Int) {
        session.moveHighlight(by: offset)
    }

    func preferHighlight(at index: Int) {
        session.preferHighlight(index)
    }

    var highlightedID: WindowID? {
        guard let index = session.highlighted, items.indices.contains(index) else {
            return nil
        }
        return items[index].id
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Pane \(model.paneIndex + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.session.buffer.isEmpty ? "–" : model.session.buffer)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(model.session.buffer.isEmpty ? .tertiary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(minWidth: 48, alignment: .trailing)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Number")
            }

            Text("Type a number, Enter to switch, Esc to cancel")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if model.items.isEmpty {
                Text("No windows in this pane")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(model.items) { item in
                            SwitcherRowView(
                                item: item,
                                isHighlighted: model.session.highlighted == item.number - 1,
                                isMatch: model.session.matchingIndices.contains(item.number - 1)
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.preferHighlight(at: item.number - 1)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .moveDisabled(!item.isAssigned)
                        }
                        .onMove(perform: onMove)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: model.session.highlighted) { _, index in
                        guard let index, model.items.indices.contains(index) else { return }
                        proxy.scrollTo(model.items[index].id, anchor: .center)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 480, height: 360)
    }
}

private struct SwitcherRowView: View {
    var item: SwitcherItem
    var isHighlighted: Bool
    var isMatch: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(item.number)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(minWidth: 28, alignment: .trailing)
                .foregroundStyle(isMatch ? .primary : .tertiary)

            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: isHighlighted ? .semibold : .medium))
                    .lineLimit(1)
                Text(item.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let pane = item.pane {
                Text("P\(pane)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Pane \(pane)")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .opacity(isMatch ? 1 : 0.38)
    }
}

enum SwitcherKeyBinding: Equatable {
    case digit(Character)
    case delete
    case confirm
    case hide
    case moveUp
    case moveDown

    static func resolve(_ event: NSEvent) -> SwitcherKeyBinding? {
        resolve(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
    }

    static func resolve(keyCode: UInt16, characters: String?) -> SwitcherKeyBinding? {
        switch keyCode {
        case 53:
            return .hide
        case 36, 76:
            return .confirm
        case 51, 117:
            return .delete
        case 126:
            return .moveUp
        case 125:
            return .moveDown
        default:
            guard let characters, let character = characters.first,
                  let value = character.wholeNumberValue, (0...9).contains(value)
            else {
                return nil
            }
            return .digit(Character(String(value)))
        }
    }
}
