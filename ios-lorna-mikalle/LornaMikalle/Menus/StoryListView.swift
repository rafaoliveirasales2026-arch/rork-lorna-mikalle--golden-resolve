import SwiftUI

/// Chapter list. The main story never needs GPS, so it is always playable.
struct StoryListView: View {
    @Environment(GameState.self) private var game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("La determinazione d'oro")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                        Text("16 September 2023. A forgotten composition wakes something in Lorna. Now a raven-pinned Famiglia is selling Polvere Nera in her streets, and only she can see what it does to the spirits.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.creamDim)
                        Label("Playable anywhere, no walking needed", systemImage: "house.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.spirit)
                            .padding(.top, 4)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Chapters") {
                    prologueRow
                    ForEach(Story.chapters) { chapter in
                        row(chapter)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.duskBackdrop.ignoresSafeArea())
            .navigationTitle("Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.gold)
    }

    private var prologueRow: some View {
        Button {
            game.playIntro()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "film.stack")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.ink.opacity(0.8)))
                    .overlay(Circle().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prologue · Before 14:10")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                    Text("Una canzone che aspetta")
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                    Text("1983, a song never played, and the life Lorna had before the gold.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.creamDim)
                        .lineLimit(3)
                }
                Spacer(minLength: 4)
                Text("Watch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.plum))
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Theme.ink.opacity(0.6))
    }

    private func row(_ chapter: Chapter) -> some View {
        let next = game.progress.storyChapter
        let locked = chapter.id > next
        let done = chapter.id < next
        let inProgress = chapter.id == next && game.progress.storyBeat > 0
        return Button {
            game.startChapter(chapter)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: locked ? "lock.fill" : chapter.symbol)
                    .font(.title3)
                    .foregroundStyle(locked ? Theme.creamDim : Theme.gold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.ink.opacity(0.8)))
                    .overlay(Circle().strokeBorder(locked ? Color.white.opacity(0.12) : Theme.gold.opacity(0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(chapter.number) · \(chapter.english)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                    Text(chapter.title)
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                    Text(locked ? "Finish the previous chapter to unlock." : chapter.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Theme.creamDim)
                        .lineLimit(3)
                }
                Spacer(minLength: 4)
                if !locked {
                    Text(done ? "Replay" : (inProgress ? "Continue" : "Play"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(done ? Theme.cream : Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(done ? AnyShapeStyle(Theme.plum) : AnyShapeStyle(Theme.goldGradient)))
                }
            }
            .padding(.vertical, 6)
        }
        .disabled(locked)
        .listRowBackground(Theme.ink.opacity(0.6))
    }
}
