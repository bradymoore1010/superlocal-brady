import SwiftUI

struct ReminderPickerView: View {
    @Bindable var store: MailStore
    @State private var options: [ReminderOption] = []
    @State private var customDate = Date().addingTimeInterval(24 * 60 * 60)

    var body: some View {
        VStack(spacing: 0) {
            PaletteSettingsHeader(title: "Remind me") {
                store.commandPaletteMode = .commands
            } onClose: {
                store.closeCommandPalette()
            }

            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        store.setReminder(at: option.date)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(MailTheme.secondaryText)
                                .frame(width: 20)

                            Text(option.label)
                                .font(MailTheme.font(13, weight: .medium))
                                .foregroundStyle(MailTheme.text)

                            Spacer()

                            Text(option.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                .font(MailTheme.font(12))
                                .foregroundStyle(MailTheme.mutedText)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option.id != options.last?.id {
                        Hairline().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)

            Hairline().padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 12) {
                Text("Custom date and time")
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)

                HStack(spacing: 12) {
                    DatePicker(
                        "Reminder date and time",
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)

                    Spacer()

                    Button("Set reminder") {
                        store.setReminder(at: customDate)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(customDate.timeIntervalSinceNow <= 30)
                }
                .frame(height: 36)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .onAppear(perform: populateOptions)
    }

    private func populateOptions() {
        let calendar = Calendar.current
        let now = Date()
        var generated: [ReminderOption] = []

        if let laterToday = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now),
           laterToday.timeIntervalSince(now) > 30 * 60 {
            generated.append(ReminderOption(id: "later-today", label: "Later today", icon: "sun.max", date: laterToday))
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           let tomorrowMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow),
           let tomorrowAfternoon = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: tomorrow) {
            generated.append(ReminderOption(id: "tomorrow-morning", label: "Tomorrow morning", icon: "sunrise", date: tomorrowMorning))
            generated.append(ReminderOption(id: "tomorrow-afternoon", label: "Tomorrow afternoon", icon: "sun.max", date: tomorrowAfternoon))
            customDate = tomorrowMorning
        }

        let weekday = calendar.component(.weekday, from: now)
        var daysUntilMonday = (2 - weekday + 7) % 7
        if daysUntilMonday == 0 { daysUntilMonday = 7 }
        if let monday = calendar.date(byAdding: .day, value: daysUntilMonday, to: calendar.startOfDay(for: now)),
           let mondayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday) {
            generated.append(ReminderOption(id: "next-monday", label: "Next Monday", icon: "calendar", date: mondayMorning))
        }

        options = generated
    }
}

private struct ReminderOption: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    let date: Date
}
