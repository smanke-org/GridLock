import GridLockKit
import SwiftUI

/// Each display's grid at the current desk. (S-006; the desk picture, desk list and
/// copy/paste come with S-023/S-024.)
struct DesksSettings: View {
    let desks: DeskTracker

    var body: some View {
        Form {
            if let desk = desks.currentDesk {
                Section {
                    LabeledContent("Desk", value: desk.name)
                    Caption("Each display keeps its own grid at each desk.")
                }
                ForEach(desks.live, id: \.key) { display in
                    DisplayGridSection(desks: desks, deskID: desk.id, display: display)
                }
            } else {
                Text("Recognizing your displays…").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplayGridSection: View {
    let desks: DeskTracker
    let deskID: UUID
    let display: LiveDisplay

    private var grid: GridSpec { desks.settings(for: display).grid }

    private func binding<T>(_ path: WritableKeyPath<GridSpec, T>) -> Binding<T> {
        Binding(get: { grid[keyPath: path] },
                set: { value in desks.store.update(desk: deskID, display: display.key) { $0.grid[keyPath: path] = value } })
    }

    var body: some View {
        Section(display.isBuiltin ? "Built-in Display" : display.name) {
            Stepper("Columns: \(grid.columns)", value: binding(\.columns), in: GridSpec.columnRange)
            Stepper("Rows: \(grid.rows)", value: binding(\.rows), in: GridSpec.rowRange)
            Stepper("Gap: \(Int(grid.gap)) pt", value: binding(\.gap), in: GridSpec.spacingRange, step: 2)
            Stepper("Margin: \(Int(grid.margin)) pt", value: binding(\.margin), in: GridSpec.spacingRange, step: 2)
        }
    }
}
