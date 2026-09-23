import SwiftUI
import VitalSnapCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var captureKind: ReadingKind?
    @State private var showsAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Photograph a display, confirm the numbers, and save them to Apple Health.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ActionCard(
                        title: "Weight",
                        subtitle: "Digital scale",
                        systemImage: "scalemass",
                        tint: Theme.blue
                    ) {
                        captureKind = .weight
                    }
                    .accessibilityIdentifier("capture.weight")
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    ActionCard(
                        title: "Blood pressure",
                        subtitle: "Cuff monitor",
                        systemImage: "waveform.path.ecg",
                        tint: Theme.coral
                    ) {
                        captureKind = .bloodPressure
                    }
                    .accessibilityIdentifier("capture.bloodPressure")
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 10, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    if model.log.readings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No readings yet")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text("A confirmed reading is listed here. On an iPhone it is also written to Apple Health.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Theme.card)
                    } else {
                        ForEach(model.log.readings) { reading in
                            ReadingRow(reading: reading)
                                .listRowBackground(Theme.card)
                        }
                        .onDelete(perform: delete)
                    }
                } header: {
                    Text("On this iPhone")
                } footer: {
                    Text("Deleting a row removes it from VitalSnap only. Apple Health keeps its own copy.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("VitalSnap")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About VitalSnap")
                }
            }
        }
        .fullScreenCover(item: $captureKind) { kind in
            CaptureView(kind: kind)
                .environment(model)
        }
        .sheet(isPresented: $showsAbout) {
            AboutView()
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { model.log.readings[$0].id }
        ids.forEach(model.log.remove)
    }
}

private struct ReadingRow: View {
    var reading: LoggedReading

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reading.kind == .weight ? "scalemass" : "waveform.path.ecg")
                .font(.body.weight(.semibold))
                .foregroundStyle(reading.kind == .weight ? Theme.blue : Theme.coral)
                .frame(width: 36, height: 36)
                .background((reading.kind == .weight ? Theme.blue : Theme.coral).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.summary)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(reading.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Text(reading.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Text(reading.savedToHealth ? "Health" : "iPhone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(reading.savedToHealth ? Theme.green : Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (reading.savedToHealth ? Theme.green : Color.primary).opacity(reading.savedToHealth ? 0.12 : 0.06),
                    in: Capsule()
                )
                .accessibilityLabel(reading.savedToHealth ? "Saved to Apple Health" : "Saved on this iPhone")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    aboutBlock(
                        title: "What it does",
                        text: "VitalSnap photographs a scale or blood pressure display, reads the digits on this iPhone, and asks you to confirm them before saving."
                    )
                    aboutBlock(
                        title: "Where readings go",
                        text: "Confirmed readings are written to Apple Health as body mass, or as a blood pressure correlation with an optional heart rate. They are also listed in VitalSnap. Nothing is sent to a server."
                    )
                    aboutBlock(
                        title: "If a number looks wrong",
                        text: "Seven-segment screens, glare, and unusual layouts can fool the reader. The parsers are heuristic. Edit the value, or type it yourself, before you save."
                    )
                    aboutBlock(
                        title: "Not a medical device",
                        text: "VitalSnap does not diagnose, grade, or interpret a reading. It stores the numbers you confirm."
                    )
                }
                .padding(24)
            }
            .background(Theme.paper)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func aboutBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel(previewData: true))
}
