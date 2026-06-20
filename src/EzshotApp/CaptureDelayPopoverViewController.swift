import AppKit
import EzshotCore

@MainActor
final class CaptureDelayPopoverViewController: NSViewController {
    private let preferences: PreferencesStore
    private let onChange: () -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let secondsLabel = NSTextField(labelWithString: "")
    private let field = NSTextField(frame: .zero)
    private let stepper = NSStepper(frame: .zero)
    private let presets = NSSegmentedControl(labels: ["", "1", "3", "5", "10"], trackingMode: .selectOne, target: nil, action: nil)
    private let presetValues: [Double] = [0, 1, 3, 5, 10]

    init(preferences: PreferencesStore, onChange: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: 118))

        field.placeholderString = "0"
        field.alignment = .right
        field.target = self
        field.action = #selector(updateFromField)

        stepper.minValue = 0
        stepper.maxValue = 999
        stepper.increment = 1
        stepper.target = self
        stepper.action = #selector(updateFromStepper)

        presets.target = self
        presets.action = #selector(updateFromPreset)
        presets.segmentStyle = .texturedRounded
        for index in presetValues.indices {
            presets.setWidth(index == 0 ? 48 : 38, forSegment: index)
        }

        for subview in [titleLabel, field, stepper, secondsLabel, presets] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            field.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            field.widthAnchor.constraint(equalToConstant: 82),

            stepper.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            stepper.centerYAnchor.constraint(equalTo: field.centerYAnchor),

            secondsLabel.leadingAnchor.constraint(equalTo: stepper.trailingAnchor, constant: 8),
            secondsLabel.centerYAnchor.constraint(equalTo: field.centerYAnchor),

            presets.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            presets.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14)
        ])

        refresh()
    }

    func refresh() {
        let localizer = AppLocalizer(preferences: preferences)
        titleLabel.stringValue = localizer.text(.delay)
        secondsLabel.stringValue = localizer.text(.seconds)
        presets.setLabel(localizer.text(.off), forSegment: 0)

        let value = preferences.captureDelaySeconds
        field.stringValue = format(value)
        stepper.doubleValue = value
        if let index = presetValues.firstIndex(where: { abs($0 - value) < 0.001 }) {
            presets.selectedSegment = index
        } else {
            presets.selectedSegment = -1
        }
    }

    private func setDelay(_ value: Double) {
        preferences.captureDelaySeconds = max(0, value)
        refresh()
        onChange()
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    @objc private func updateFromField() {
        setDelay(field.doubleValue)
    }

    @objc private func updateFromStepper() {
        setDelay(stepper.doubleValue)
    }

    @objc private func updateFromPreset() {
        let index = presets.selectedSegment
        guard presetValues.indices.contains(index) else {
            return
        }

        setDelay(presetValues[index])
    }
}
