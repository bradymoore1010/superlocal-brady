import SwiftUI

struct PaletteSettingsHeader: View {
    let title: String
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to commands")

            Text(title)
                .font(MailTheme.font(15, weight: .medium))
                .foregroundStyle(MailTheme.text)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 6)
        .frame(height: 54)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct ScheduleSendView: View {
    @Bindable var store: MailStore
    @State private var options: [ScheduleOption] = []
    @State private var selectedID = ""
    @State private var customDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            PaletteSettingsHeader(title: "Schedule send") {
                store.commandPaletteMode = .commands
            } onClose: {
                store.closeCommandPalette()
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Suggested time")
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.secondaryText)

                    Picker("Suggested time", selection: $selectedID) {
                        ForEach(options) { option in
                            Text(option.title).tag(option.id)
                        }
                        Text("Custom date and time…").tag("custom")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(MailTheme.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(MailTheme.border, lineWidth: 1)
                    }
                }

                if selectedID == "custom" {
                    HStack(spacing: 12) {
                        dateField("Date", components: .date)
                        dateField("Time", components: .hourAndMinute)
                    }
                }

                Text(summary)
                    .font(MailTheme.font(13))
                    .foregroundStyle(MailTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(MailTheme.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                HStack {
                    if !hasReplyContent {
                        Text("Write a reply first.")
                            .font(MailTheme.font(12))
                            .foregroundStyle(MailTheme.secondaryText)
                    }

                    Spacer()

                    Button("Cancel") {
                        store.commandPaletteMode = .commands
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Schedule send") {
                        guard let date = selectedDate else { return }
                        store.scheduleReply(at: date)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSchedule)
                    .opacity(canSchedule ? 1 : 0.5)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
            .padding(.top, 16)
            .padding(.bottom, 6)
        }
        .onAppear(perform: populateOptions)
    }

    private func dateField(_ title: String, components: DatePickerComponents) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(MailTheme.font(12))
                .foregroundStyle(MailTheme.secondaryText)
            DatePicker(title, selection: $customDate, in: Date()..., displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 8)
                .background(MailTheme.white)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(MailTheme.border, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedDate: Date? {
        if selectedID == "custom" { return customDate }
        return options.first { $0.id == selectedID }?.date
    }

    private var hasReplyContent: Bool {
        !store.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.replyAttachments.isEmpty
    }

    private var canSchedule: Bool {
        hasReplyContent && (selectedDate.map { $0 > Date() } ?? false)
    }

    private var summary: String {
        guard let selectedDate, selectedDate > Date() else {
            return "Choose a future date and time."
        }
        return "This reply will send \(Self.formatter.string(from: selectedDate))."
    }

    private func populateOptions() {
        let calendar = Calendar.current
        let now = Date()
        var generated: [ScheduleOption] = []

        if let todayAtFive = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now),
           todayAtFive.timeIntervalSince(now) > 30 * 60 {
            generated.append(ScheduleOption(id: "later-today", label: "Later today", date: todayAtFive))
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           let tomorrowMorning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow),
           let tomorrowAfternoon = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: tomorrow) {
            generated.append(ScheduleOption(id: "tomorrow-morning", label: "Tomorrow morning", date: tomorrowMorning))
            generated.append(ScheduleOption(id: "tomorrow-afternoon", label: "Tomorrow afternoon", date: tomorrowAfternoon))
            customDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }

        let weekday = calendar.component(.weekday, from: now)
        var daysUntilMonday = (2 - weekday + 7) % 7
        if daysUntilMonday == 0 { daysUntilMonday = 7 }
        if let monday = calendar.date(byAdding: .day, value: daysUntilMonday, to: calendar.startOfDay(for: now)),
           let mondayMorning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: monday) {
            generated.append(ScheduleOption(id: "next-monday", label: "Next Monday", date: mondayMorning))
        }

        options = generated
        selectedID = generated.first?.id ?? "custom"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter
    }()
}

private struct ScheduleOption: Identifiable {
    let id: String
    let label: String
    let date: Date

    var title: String {
        "\(label) · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
    }
}
