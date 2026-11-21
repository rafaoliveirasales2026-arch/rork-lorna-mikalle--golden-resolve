import SwiftUI

enum Speaker: Equatable {
    case narrator, lorna
    case person(Person)
    case spirit(SpiritKind)
    case other(String)

    var name: String {
        switch self {
        case .narrator: ""
        case .lorna: "Lorna"
        case .person(let p): p.shortName
        case .spirit(let k): k.name
        case .other(let n): n
        }
    }

    var tint: Color {
        switch self {
        case .narrator: Theme.creamDim
        case .lorna: Theme.gold
        case .person(let p): p.tint
        case .spirit(let k): k.glowColor
        case .other: Theme.spirit
        }
    }
}

struct StoryChoice {
    let label: String
    let reply: [(Speaker, String)]
    var affinity: (Person, Int)? = nil
    var alarm: Int = 0
}

enum StoryBeat {
    /// Location card: place, time.
    case scene(String, String)
    case line(Speaker, String)
    case choice([StoryChoice])
    case battle(EnemyProfile, ally: Person?)
    /// Chapter 4 stealth: if the alarm is full, a guard fight starts here.
    case alarmCheck
    case join(Person)
    case reward(Reward)
}

struct Chapter: Identifiable {
    let id: Int
    let title: String
    let english: String
    let blurb: String
    let symbol: String
    let usesAlarm: Bool
    let beats: [StoryBeat]

    var number: String { "Chapter \(id + 1)" }
}

/// The main story. Playable anywhere: it never needs GPS.
enum Story {
    static let chapters: [Chapter] = [chapter1, chapter2, chapter3, chapter4, chapter5, chapter6]

    // MARK: 1
    static let chapter1 = Chapter(
        id: 0, title: "Il 16 settembre", english: "September 16th",
        blurb: "A music lesson, a forgotten composition, and a light only Lorna can see.",
        symbol: "music.note", usesAlarm: false,
        beats: [
            .scene("Liceo Galilei · Aula 3B", "16 September 2023 · 14:10"),
            .line(.narrator, "The last lesson of a hot Saturday. Half the class is asleep. The other half is pretending to read."),
            .line(.person(.benassi), "Before you escape: one piece. I wrote it forty years ago and never played it for anyone. It is called \u{201C}La determinazione d'oro\u{201D}."),
            .line(.lorna, "(Why is he looking at me while he says that?)"),
            .line(.narrator, "The first chord fills the room. The dust in the sunlight stops falling. Literally stops, mid-air."),
            .line(.narrator, "A warm gold rises in Lorna's chest, climbs to her fingertips, and spills over the desk like honey."),
            .line(.person(.benassi), "\u{2026}Ah. So it was you. Go home, Signorina Mikalle. Walk slowly. Look up."),
            .scene("Via dei Fornai", "17:40 · golden hour"),
            .line(.narrator, "A boy is sitting on the bus stop roof, holding a paper lantern. He is see-through. Nobody else notices."),
            .line(.spirit(.lanternWisp), "\u{201C}You can see me? Then help me \u{2014} or leave this street. It's getting dark in a bad way.\u{201D}"),
            .choice([
                StoryChoice(label: "\u{201C}I'll help you.\u{201D}", reply: [(.spirit(.lanternWisp), "\u{201C}Brave. Or silly. Hold still \u{2014} I'm scared, and scared spirits bite.\u{201D}")]),
                StoryChoice(label: "\u{201C}Am I dreaming?\u{201D}", reply: [(.spirit(.lanternWisp), "\u{201C}Dreams don't smell like the bakery. Now hold still \u{2014} I'm scared, and scared spirits bite.\u{201D}")]),
            ]),
            .battle(.spirit(.lanternWisp, level: 1).eased(hp: 0.6, attack: 0.55), ally: nil),
            .line(.spirit(.lanternWisp), "\u{201C}Oh. Your gold is warm. The black powder made me cold.\u{201D}"),
            .line(.lorna, "Black powder?"),
            .line(.narrator, "Behind the bakery, two men in black suits with raven pins pass a small package to a teenager. One of them laughs too loudly."),
            .line(.other("Raven-pin man"), "\u{201C}Polvere Nera. First taste is free. Tell your friends the Famiglia is generous.\u{201D}"),
            .line(.narrator, "Lorna's hand is still glowing. She hides it in her pocket and runs home."),
            .scene("Casa Mikalle", "20:15"),
            .line(.person(.ottavia), "You're late, you're pale and your hand is shining. Sit. Eat. Then lie to me properly."),
            .line(.lorna, "Nonna, you burned your hand on the pot again."),
            .line(.narrator, "Lorna touches the burn. Gold light. The red fades like it was never there."),
            .line(.person(.ottavia), "\u{2026}Madonna santa. Your grandfather used to hum that song too. Eat. We'll talk tomorrow."),
            .join(.ottavia),
            .reward(Reward(xp: 300, items: [.cornetto: 2])),
        ])

    // MARK: 2
    static let chapter2 = Chapter(
        id: 1, title: "Spiriti di quartiere", english: "Neighbourhood Spirits",
        blurb: "A classmate sees too much. The fountain calls a meeting.",
        symbol: "drop.fill", usesAlarm: false,
        beats: [
            .scene("Liceo Galilei · courtyard", "Monday · 10:05"),
            .person(.giulia, "You. Mikalle. Why were you glowing behind the bakery on Saturday? And don't say \u{201C}sunscreen\u{201D}."),
            .choice([
                StoryChoice(label: "Tell her the truth", reply: [(.person(.giulia), "Spirits. Gold powers. Okay. That's the best thing that's happened this year.")], affinity: (.giulia, 40)),
                StoryChoice(label: "\u{201C}It was sunscreen.\u{201D}", reply: [(.person(.giulia), "I literally said don't say sunscreen. Fine. I'm following you after school anyway.")], affinity: (.giulia, 15)),
            ]),
            .line(.narrator, "Giulia draws everything: teachers, pigeons, the man who sells lottery tickets. Lately she has been drawing people with raven pins."),
            .scene("Piazza della Fontana", "Midnight"),
            .line(.narrator, "Every spirit in the quarter is sitting around the fountain like it's a condominium meeting. The Bell Tower Crow is taking minutes."),
            .line(.spirit(.bellTowerCrow), "\u{201C}CAW. Item one: the humans with raven pins. Item two: who keeps throwing chewing gum in the fountain.\u{201D}"),
            .line(.spirit(.fontanaNymph), "\u{201C}Item two is more urgent. But fine. The Famiglia Corvonero sells Polvere Nera. It makes humans hollow \u{2014} and hollow humans make spirits angry.\u{201D}"),
            .line(.spirit(.fontanaNymph), "\u{201C}You, golden girl. The angry ones are coming. One already turned to ash.\u{201D}"),
            .line(.person(.giulia), "I can see them too?! Lorna, I can SEE THEM. Is it contagious? Is it like a cold?"),
            .line(.spirit(.echoChild), "\u{201C}Is it like a cold? \u{2026}a cold? \u{2026}cold?\u{201D}"),
            .line(.narrator, "The fountain water turns grey. Something made of smoke and old anger rises from the drain."),
            .battle(.spirit(.ashenVeil, level: 2).eased(hp: 0.7, attack: 0.6), ally: .giulia),
            .line(.spirit(.ashenVeil), "\u{201C}\u{2026}I just wanted the street to be quiet again.\u{201D}"),
            .line(.lorna, "Then help us make it quiet. For real this time."),
            .line(.person(.giulia), "Team name: \u{201C}Le Gialle\u{201D}. No, wait. That sounds like a taxi company. I'll think about it."),
            .join(.giulia),
            .reward(Reward(xp: 400, items: [.espresso: 2, .auraShard: 1])),
        ])

    // MARK: 3
    static let chapter3 = Chapter(
        id: 2, title: "Il caffè che sapeva troppo", english: "The Coffee That Knew Too Much",
        blurb: "Bar Stella's espresso machine is haunted, and it heard everything.",
        symbol: "cup.and.saucer.fill", usesAlarm: false,
        beats: [
            .scene("Bar Stella", "Tuesday · 07:30"),
            .line(.narrator, "Teo Ricci is fixing Bar Stella's Wi-Fi in exchange for unlimited cornetti. The espresso machine hisses at him. Personally."),
            .line(.other("Signor Gaggia (the machine)"), "\u{201C}PSSSH. Fifty-two years I've made coffee here. I hear everything said at this counter. EVERYTHING.\u{201D}"),
            .line(.person(.teo), "Lorna. The coffee machine is talking. I haven't slept, but I think it's talking."),
            .line(.other("Signor Gaggia"), "\u{201C}The ravens order here every Thursday. Doppio, no sugar, terrible tippers. They talk about routes.\u{201D}"),
            .choice([
                StoryChoice(label: "Ask about the routes", reply: [(.other("Signor Gaggia"), "\u{201C}Couriers on scooters. Via Roma at nine, the old cinema at ten. The phone they use is always the same.\u{201D}")]),
                StoryChoice(label: "Order an espresso first", reply: [(.other("Signor Gaggia"), "\u{201C}FINALLY someone with manners. Via Roma at nine, the old cinema at ten. The phone is always the same.\u{201D}")], affinity: (.teo, 10)),
            ]),
            .line(.person(.teo), "If I can clone that phone's messages\u{2026} we'd see the whole network. Just saying. Hypothetically. I'm in."),
            .scene("Via Roma", "21:02"),
            .line(.narrator, "A courier spots Teo's phone pointed at him. He drops his scooter and runs straight at Lorna."),
            .line(.narrator, "She closes her eyes. A pull, like falling up \u{2014} and she is standing three metres behind him."),
            .line(.lorna, "\u{2026}I teleported. I teleported?! Teo, did you see that?"),
            .line(.person(.teo), "I saw it and I'm choosing to have a calm reaction later."),
            .battle(.courier.eased(hp: 0.85, attack: 0.8), ally: .teo),
            .line(.person(.teo), "Got the phone mirrored. Names, times, a warehouse at the old Corvo tannery. And a party. Saturday."),
            .line(.other("Signor Gaggia"), "\u{201C}PSSSH. Bring me a new rubber gasket when you're done saving the city.\u{201D}"),
            .join(.teo),
            .reward(Reward(xp: 450, items: [.santino: 1, .auraShard: 1])),
        ])

    // MARK: 4
    static let chapter4 = Chapter(
        id: 3, title: "Infiltrazione", english: "Infiltration",
        blurb: "A waitress uniform, a raven party, and one very loud alarm.",
        symbol: "theatermasks.fill", usesAlarm: true,
        beats: [
            .scene("Ex Conceria Corvo", "Saturday · 22:30"),
            .line(.person(.giulia), "Uniform, fake name tag, hair up. You are now \u{201C}Loredana\u{201D}, nineteen, catering student. Don't glow."),
            .line(.person(.teo), "I'm in the van with the cameras. Every time you look suspicious, the alarm goes up. Please don't make it go up."),
            .line(.narrator, "A guard at the door checks a list. Lorna is not on the list."),
            .choice([
                StoryChoice(label: "\u{201C}I'm with catering. The tiramisù won't carry itself.\u{201D}", reply: [(.other("Guard"), "\u{201C}\u{2026}Go. Leave one for me.\u{201D}")], alarm: 10),
                StoryChoice(label: "Teleport past him", reply: [(.person(.teo), "That was very cool and a camera saw a girl appear out of nothing.")], alarm: 40),
                StoryChoice(label: "Wait for a distraction", reply: [(.spirit(.bellTowerCrow), "\u{201C}CAW!\u{201D} (A crow steals the guard's sunglasses.)")], alarm: 0),
            ]),
            .line(.narrator, "Inside: chandeliers, cheap champagne, and men pretending a tannery is a palace. Rocco Ferraccio laughs at the center of the room."),
            .line(.person(.rocco), "\u{201C}The schools are our best market. Kids pay, kids talk, kids come back.\u{201D}"),
            .choice([
                StoryChoice(label: "Keep serving, stay calm", reply: [(.lorna, "(Breathe. Smile. Bruschetta.)")], alarm: 5),
                StoryChoice(label: "Accidentally spill wine on him", reply: [(.person(.rocco), "\u{201C}Ragazzina! Do you know what this suit cost?\u{201D}")], alarm: 30),
                StoryChoice(label: "Slip toward the office", reply: [(.person(.teo), "Office door, left of the stairs. Two guards. Hurry.")], alarm: 15),
            ]),
            .alarmCheck,
            .scene("Ex Conceria · office", "23:10"),
            .line(.narrator, "A safe. A ledger with ravens on the cover. And taped to the wall: a photo of Prof. Benassi, circled in red."),
            .line(.lorna, "Why do they want the Professor?"),
            .choice([
                StoryChoice(label: "Photograph the ledger", reply: [(.person(.teo), "Got it. Half of it is in code. Ugh. Of course it is.")], alarm: 10),
                StoryChoice(label: "Take the whole ledger", reply: [(.person(.giulia), "Bold. Very bold. Running now?")], alarm: 35),
            ]),
            .alarmCheck,
            .line(.person(.rocco), "\u{201C}Loredana. Or whatever your name is. Nobody leaves my party early.\u{201D}"),
            .battle(.rocco, ally: nil),
            .line(.person(.rocco), "\u{201C}The Don will hear about the girl with the golden hands\u{2026}\u{201D}"),
            .line(.narrator, "Sirens in the distance. Not police \u{2014} Teo's van, playing sirens through a speaker. Everyone runs."),
            .reward(Reward(xp: 700, items: [.auraShard: 2, .gelato: 1])),
        ])

    // MARK: 5
    static let chapter5 = Chapter(
        id: 4, title: "Alleati inattesi", english: "Unexpected Allies",
        blurb: "A courier who wants out. A police officer who was never a barista.",
        symbol: "person.2.wave.2.fill", usesAlarm: false,
        beats: [
            .scene("Rooftops above Via dei Fornai", "Sunday · 01:20"),
            .line(.narrator, "Someone has been following Lorna across the rooftops. Quietly, like a cat. Then he waves."),
            .line(.person(.dario), "Relax. I'm Dario. They call me Il Gatto because I land on my feet. I deliver for the ravens. Delivered. Past tense, as of tonight."),
            .line(.person(.dario), "My little brother tried the Polvere. He's okay now. I want them gone. I know every route."),
            .choice([
                StoryChoice(label: "\u{201C}Why should I trust you?\u{201D}", reply: [(.person(.dario), "You shouldn't. But I brought cornetti. That's a start.")], affinity: (.dario, 20)),
                StoryChoice(label: "\u{201C}Welcome to the team.\u{201D}", reply: [(.person(.dario), "Just like that? Okay. I like you, Golden Girl.")], affinity: (.dario, 40)),
            ]),
            .scene("Bar Stella", "Sunday · 09:00"),
            .line(.narrator, "The new barista \u{2014} the one who never smiles and makes terrible cappuccino \u{2014} sits down at their table and flips a badge."),
            .line(.person(.vittoria), "Vittoria Sangalli, Carabinieri. Undercover for eight months. You kids got further in one week than my whole unit."),
            .line(.person(.vittoria), "I can't arrest anyone without that ledger decoded. And I can't decode it without the key."),
            .line(.spirit(.bellTowerCrow), "\u{201C}CAW. The key is a song. The Don hums it when he writes. I sit on his windowsill. I hear things.\u{201D}"),
            .line(.person(.teo), "A song-cipher. The notes are the letters. Lorna\u{2026} which song?"),
            .line(.lorna, "\u{2026}La determinazione d'oro."),
            .scene("Porto Vecchio", "Sunday · 23:50"),
            .line(.narrator, "Nina \u{201C}La Lama\u{201D} waits at the end of the pier. Red coat, two blades, no hurry at all."),
            .line(.person(.nina), "\u{201C}Dario. I taught you to ride. And this is how you thank me?\u{201D}"),
            .line(.person(.dario), "You taught me to run. She's teaching me to stop."),
            .battle(.nina, ally: .vittoria),
            .line(.person(.nina), "\u{201C}Your gold\u{2026} it felt like my mother's kitchen. Tell the Don\u{2026} no. I'll tell him myself. Somewhere far from here.\u{201D}"),
            .line(.narrator, "Nina drops her blades into the sea and walks away. Vittoria lets her go. Nobody says anything for a long time."),
            .join(.dario),
            .join(.vittoria),
            .reward(Reward(xp: 800, items: [.auraShard: 3, .santino: 1])),
        ])

    // MARK: 6
    static let chapter6 = Chapter(
        id: 5, title: "La determinazione d'oro", english: "The Golden Determination",
        blurb: "A bell tower at sunset. A raven king. One song to end it.",
        symbol: "bell.fill", usesAlarm: false,
        beats: [
            .scene("Prof. Benassi's apartment", "Monday · 18:00"),
            .line(.person(.benassi), "I wrote the piece in 1983, after the Corvo family burned my father's music shop. I didn't know it would wake anyone. I just wanted it to be brave."),
            .line(.person(.benassi), "Saverio Corvo heard it once. He's been trying to own it ever since. He thinks a song that wakes spirits can command them."),
            .line(.lorna, "It can't. It doesn't command. It just\u{2026} makes you decide."),
            .line(.person(.benassi), "Then decide, Lorna. The Don has taken the bell tower. He means to ring it at sunset and call every angry spirit in the city."),
            .scene("Torre Civica", "Monday · 19:12 · sunset"),
            .line(.narrator, "Ravens on every ledge. The real kind and the kind in suits. At the top, Don Saverio Corvo holds the bell rope like a conductor's baton."),
            .line(.person(.saverio), "\u{201C}A schoolgirl. Benassi sent me a schoolgirl. Do you know how many people work for me, child?\u{201D}"),
            .choice([
                StoryChoice(label: "\u{201C}Fewer than yesterday.\u{201D}", reply: [(.person(.dario), "Ha! Fewer than yesterday!")], affinity: (.dario, 20)),
                StoryChoice(label: "\u{201C}Ring it. See who comes.\u{201D}", reply: [(.person(.saverio), "\u{201C}\u{2026}Insolent.\u{201D}")]),
            ]),
            .line(.narrator, "He pulls the rope. The bell rings once. Thirteen spirits rise from the streets below \u{2014} and none of them look at him."),
            .line(.spirit(.lanternWisp), "\u{201C}We came for her. Not for you.\u{201D}"),
            .battle(.saverio, ally: .ottavia),
            .line(.narrator, "Lorna hums. Not loud. The first four notes. Every spirit in the tower hums with her, and the ravens finally go quiet."),
            .line(.person(.vittoria), "Ledger decoded. Forty-one names, three warehouses, one very upset Don. Famiglia Corvonero is finished."),
            .line(.person(.saverio), "\u{201C}\u{2026}It was only a song.\u{201D}"),
            .line(.lorna, "It was never only a song."),
            .scene("Liceo Galilei · Aula 3B", "Tuesday · 08:00"),
            .line(.person(.benassi), "Homework: write one page on what determination means to you. Signorina Mikalle, you may write two."),
            .line(.person(.giulia), "Team name: \u{201C}Le Determinate\u{201D}. Final answer."),
            .line(.narrator, "Outside the window, a boy with a paper lantern waves. The streets are still full of spirits. Lorna still has a lot of walking to do."),
            .reward(Reward(xp: 1500, items: [.auraShard: 5, .gelato: 2])),
        ])
}

private extension StoryBeat {
    static func person(_ p: Person, _ text: String) -> StoryBeat { .line(.person(p), text) }
}
