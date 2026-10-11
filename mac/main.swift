// Clawd Desktop Pet for macOS - a tiny pixel companion that lives above your Dock.
// Unofficial fan project, not affiliated with Anthropic.
// Build: mac/build.sh (needs the Xcode command line tools)

import Cocoa
import CryptoKit
import ServiceManagement

// MARK: - Settings

func T(_ de: String, _ en: String) -> String { return Cfg.lang == "de" ? de : en }

enum Cfg {
    static let orange = "#F26522"

    static var lang = (Locale.preferredLanguages.first ?? "en").hasPrefix("de") ? "de" : "en"
    static var size = 5
    static var talk = false
    static var color = orange
    static var firstRun = true
    static var readOnly = false

    // Progress: feeding and petting earn XP; levels unlock tricks, colours and hats
    static var xp = 0
    static var food = 80.0   // 0 = starving, 100 = full
    static var hat = "none"

    static let sizeVals = [3, 5, 7, 10]
    static let colVals = [orange, "#F06FA8", "#4A90D9", "#3FA66B", "#9B6FE8", "#3DD6D0", "#E8B923"]
    static let colLevel = [1, 1, 1, 2, 3, 4, 5]
    static let hatVals = ["none", "cap", "party", "phones", "tophat", "crown"]
    static let hatLevel = [1, 1, 1, 2, 4, 6]

    static var level: Int { return 1 + Int((Double(xp) / 15.0).squareRoot()) }
    static func xpFor(_ level: Int) -> Int { return 15 * (level - 1) * (level - 1) }

    static var sizeLabels: [String] { return [T("Klein", "Small"), T("Mittel", "Medium"), T("Groß", "Large"), T("Riesig", "Huge")] }
    static var colLabels: [String] { return ["Orange", "Pink", T("Blau", "Blue"), T("Grün", "Green"), T("Lila", "Purple"), T("Türkis", "Teal"), "Gold"] }
    static var hatLabels: [String] { return [T("Ohne", "None"), T("Mütze", "Beanie"), T("Partyhut", "Party hat"), T("Kopfhörer", "Headphones"), T("Zylinder", "Top hat"), T("Krone", "Crown")] }

    static func load() {
        let d = UserDefaults.standard
        if let l = d.string(forKey: "lang") {
            lang = l == "de" ? "de" : "en"
            firstRun = false
        }
        if d.object(forKey: "size") != nil { size = max(2, min(12, d.integer(forKey: "size"))) }
        talk = d.bool(forKey: "talk")
        if let c = d.string(forKey: "color"), c.hasPrefix("#") { color = c }
        xp = max(0, d.integer(forKey: "xp"))
        if d.object(forKey: "food") != nil { food = max(0, min(100, d.double(forKey: "food"))) }
        if let h = d.string(forKey: "hat"), hatVals.contains(h) { hat = h }
        // He also gets hungry while the Mac is off - but slowly, and never all the way
        let stamp = d.double(forKey: "stamp")
        if stamp > 0 {
            let hours = (Date().timeIntervalSince1970 - stamp) / 3600
            if hours > 0 { food = max(min(food, 20), food - hours * 8) }
        }
    }

    static func save() {
        if readOnly { return }
        let d = UserDefaults.standard
        d.set(lang, forKey: "lang")
        d.set(size, forKey: "size")
        d.set(talk, forKey: "talk")
        d.set(color, forKey: "color")
        d.set(xp, forKey: "xp")
        d.set(food, forKey: "food")
        d.set(hat, forKey: "hat")
        d.set(Date().timeIntervalSince1970, forKey: "stamp")
    }

    // "Open at login" needs macOS 13 or newer.
    static var canAutoStart: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var autoStart: Bool {
        get {
            if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
            return false
        }
        set {
            if readOnly { return }
            if #available(macOS 13.0, *) {
                if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            }
        }
    }
}

// MARK: - Colours

func hex(_ s: String) -> NSColor {
    var h = s
    if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    let a: CGFloat = h.count == 8 ? CGFloat((v >> 24) & 0xFF) / 255 : 1
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

enum Ink {
    static let ink = hex("#1A1915"), white = hex("#FFFFFF"), cream = hex("#FAF9F5"), red = hex("#E5484D")
    static let yellow = hex("#F5C542"), blue = hex("#4A90D9"), grey = hex("#C9C8C2"), greyDark = hex("#8A8983")
    static let brown = hex("#8B5A2B"), brownDark = hex("#5C3A1A"), cookie = hex("#D9A55B"), gold = hex("#E8C76A")
    static let steam = hex("#BBFFFFFF"), green = hex("#3FA66B"), shine = hex("#6E6D68"), purple = hex("#9B6FE8")
    static let pink = hex("#F06FA8"), hatBlue = hex("#3B6FD4"), crownGold = hex("#F2B824"), teal = hex("#3DD6D0")
    static let palette = [red, yellow, blue, green, purple, pink, hex("#FF9F43"), hex("#3DD6D0")]
}

var isDark: Bool {
    return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

// MARK: - The pet

struct Particle {
    var kind = 0
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, life = 0.0, max = 0.0, size = 0.0
    var text = ""
    var color = NSColor.white
}

// Another app's window, used as a platform to stand on.
struct Plat {
    var id = 0
    var l = 0.0, t = 0.0, r = 0.0, b = 0.0
    var stand = false
}

final class Pet: NSView {
    // Canvas size in cells (one cell = one "pixel" of Clawd)
    static let CW = 48.0, CH = 36.0
    let pText = 0, pHeart = 1, pSteam = 2, pCrumb = 3
    let eyeOpen = 0, eyeClosed = 1, eyeHappy = 2, eyeWide = 3, eyeDizzy = 4

    static let heart = [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
    static let balloon = ["..XXXX..", ".XXXXXX.", "XXoXXXXX", "XXoXXXXX", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", "..XXXX..", "...XX..."]
    static let cookieBmp = [".XX.", "XdXX", "XXdX", ".XX."]

    // Speech bubble lines: [German, English]
    static let petLines = [
        ["Hihi!", "Das kitzelt!", "Mehr davon!", "Du bist nett!", "Schnurr...", "Nochmal!", "Hach, schön."],
        ["Hehe!", "That tickles!", "More, please!", "You're nice!", "Purr...", "Again!", "Ahh, lovely."]]
    static let idleLines = [
        ["Was machst du da?", "Schöner Desktop!", "Ich bin Clawd!", "Zeit für eine Pause?", "Trink mal Wasser!", "Du schaffst das!", "Mir ist langweilig...", "Psst... Speichern nicht vergessen!", "Klick mich mal an!"],
        ["What are you up to?", "Nice desktop!", "I'm Clawd!", "Time for a break?", "Drink some water!", "You've got this!", "I'm bored...", "Psst... don't forget to save!", "Click me!"]]
    static let ideaLines = [
        ["Idee!", "Heureka!", "Was wäre, wenn...", "42!", "Ich hab's!"],
        ["Idea!", "Eureka!", "What if...", "42!", "Got it!"]]
    static let codeLines = [
        ["Nur noch ein Bug...", "Kompiliert!", "Läuft bei mir.", "git push --force?", "Wer hat das geschrieben? ...Ich."],
        ["Just one more bug...", "It compiles!", "Works on my machine.", "git push --force?", "Who wrote this? ...Me."]]
    static let dragLines = [
        ["Huch!", "Hey, lass mich runter!", "Wohin geht's?", "Ich kann fliegen!"],
        ["Whoa!", "Hey, put me down!", "Where are we going?", "I can fly!"]]
    static let codeBits = ["{ }", "</>", "01", "fn", "==", "//", "[ ]", ";"]

    static let actNames = ["walk", "run", "sleep", "code", "coffee", "read", "dance", "jump", "flip", "wave", "think", "cool", "climb", "juggle", "balloon", "stretch", "chase"]
    static let actWeights = [30, 0, 6, 0, 6, 6, 5, 3, 0, 4, 0, 4, 0, 0, 0, 4, 0]
    static let actLabelsEn = ["Walk", "Zoom", "Sleep", "Code", "Drink coffee", "Read", "Dance", "Hop", "Flip", "Wave", "Think", "Be cool", "Climb the wall", "Juggle", "Balloon ride", "Stretch", "Chase the mouse"]
    static let actLabelsDe = ["Spazieren", "Flitzen", "Schlafen", "Programmieren", "Kaffee trinken", "Lesen", "Tanzen", "Hüpfen", "Salto", "Winken", "Nachdenken", "Cool sein", "Wand hochklettern", "Jonglieren", "Ballonfahrt", "Strecken", "Maus jagen"]
    static let demoScript = ["wave", "walk", "code", "coffee", "read", "dance", "jump", "flip", "cool", "juggle", "pet", "eat", "stretch", "sleep", "chase", "climb", "balloon"]
    static let busy = ["drag", "fall", "dizzy", "pet", "eat", "jump", "flip", "climb", "balloon", "chase"]

    static func actLevel(_ name: String) -> Int {
        return name == "flip" ? 2 : name == "juggle" ? 3 : name == "balloon" ? 4 : name == "climb" ? 5 : 1
    }

    var parts: [Particle] = []
    var S = 5.0
    var scale = 2.0          // device pixels per point
    var screenH = 900.0      // height of the main screen, to convert from Cocoa's bottom-left origin
    var workL = 0.0, workT = 0.0, workR = 1440.0, workB = 900.0

    // State
    var st = "idle", lastAct = ""
    var t = 0.0, dur = 0.0, anim = 0.0, x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, tx = 0.0, rot = 0.0
    var climbTop = 0.0, spawnT = 0.0, hopT = 0.0, blinkT = 2.0, maxImpact = 0.0
    var phase = 0, hops = 0, side = 0, dir = 1
    var air = false, moving = false
    var curX = 0.0, curY = 0.0
    var winLeft = 0.0, ox = 0.0, oy = 0.0
    var last = CACurrentMediaTime()
    var bodyColor = hex(Cfg.orange)

    // Reacting to the user
    var keyCount: UInt32 = 0
    var typingT = 99.0, tapT = 0.0
    var tapArm = 0
    var typed = false, wasAway = false

    // Other windows as platforms
    var plats: [Plat] = []
    var perch = 0            // window he is standing on (0 = the Dock / bottom of the screen)
    var scanT = 0.0
    let myPid = Int(ProcessInfo.processInfo.processIdentifier)

    // Hunger, level
    var beat = 0.0
    var musicDance = false
    var petXpT = 0.0, saveT = 60.0, hungerNag = 20.0, hungerShow = 0.0

    // Demo modes and admin
    var demo = false
    var demoIdx = 0
    var adminOn = false, featDemo = false, fdMusic = false
    var fdStep = 0, fdXp = 0
    var fdT = 0.0, fdFood = 0.0
    var fdHat = "none"

    // Mouse
    var pressed = false, dragging = false, menuOpen = false
    var pressX = 0.0, pressY = 0.0, grabX = 0.0, grabY = 0.0, thvx = 0.0, thvy = 0.0

    // Speech bubble
    var bubbleText = ""
    var bubbleT = 0.0, bubbleAge = 0.0
    var bubbleSit = false

    var logPath: String?
    var logT = 0.0
    var onMenu: ((NSEvent) -> Void)?

    override var isFlipped: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    var W: Double { return Pet.CW * S }
    var H: Double { return Pet.CH * S }

    // MARK: Start

    func start() {
        readScreen()
        applyScale()
        applyColor()
        x = workL + (workR - workL) / 2
        y = max(workT + 14 * S, workB - 150 * S)
        keyCount = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        set("fall")
        air = true
        let hr = Calendar.current.component(.hour, from: Date())
        say(hr < 5 ? T("Noch wach?", "Still up?") : hr < 11 ? T("Guten Morgen!", "Good morning!") : hr < 18 ? T("Hallo! Ich bin Clawd.", "Hi! I'm Clawd.") : T("Guten Abend!", "Good evening!"), 4)
        place()
    }

    func readScreen() {
        guard let scr = NSScreen.screens.first else { return }
        screenH = Double(scr.frame.height)
        let v = scr.visibleFrame
        workL = Double(v.minX)
        workR = Double(v.maxX)
        workT = screenH - Double(v.maxY)
        workB = screenH - Double(v.minY)
        scale = Double(scr.backingScaleFactor)
    }

    func applyScale() {
        S = Double(Cfg.size)
        window?.setContentSize(NSSize(width: W, height: H))
        setFrameSize(NSSize(width: W, height: H))
    }

    func applyColor() { bodyColor = hex(Cfg.color) }

    func log(_ text: String) {
        guard let p = logPath else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        let line = f.string(from: Date()) + " " + text + "\n"
        if let h = FileHandle(forWritingAtPath: p) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? line.write(toFile: p, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Mouse

    func readCursor() {
        let m = NSEvent.mouseLocation
        curX = Double(m.x)
        curY = screenH - Double(m.y)
    }

    override func mouseDown(with e: NSEvent) {
        readCursor()
        if e.clickCount == 2 {
            if !air && y >= ground - 1 { set(Cfg.level >= Pet.actLevel("flip") || demo ? "flip" : "jump") }
            return
        }
        pressed = true
        pressX = curX
        pressY = curY
        grabX = x - curX
        grabY = y - curY
        thvx = 0
        thvy = 0
    }

    override func mouseUp(with e: NSEvent) {
        if !pressed { return }
        pressed = false
        if dragging {
            dragging = false
            set("fall")
            air = true
            let lim = 500 * S
            vx = max(-lim, min(lim, thvx))
            vy = max(-lim, min(lim, thvy))
            if abs(vx) + abs(vy) > 150 * S { say(T("Huiii!", "Wheee!"), 1.5) }
        } else if st == "sleep" {
            set("idle")
            say(T("Hm? Bin wach!", "Huh? I'm awake!"), 2.5)
        } else {
            petIt()
        }
    }

    override func rightMouseDown(with e: NSEvent) { onMenu?(e) }

    func petIt() {
        set("pet")
        for _ in 0..<4 {
            spawn(pHeart, -6 + R() * 12, -11 - R() * 3, (R() - 0.5) * 3, -5 - R() * 3, 1.3 + R() * 0.5, "", 0, pal())
        }
        say(pick(Pet.petLines), 2)
        if petXpT <= 0 {
            petXpT = 8
            addXp(1)
        }
    }

    func feed() {
        if dragging { return }
        hungerShow = 0
        if Cfg.food >= 85 {
            say(T("Ich bin pappsatt!", "I'm stuffed!"), 2.5)
            return
        }
        set("eat")
        Cfg.food = min(100, Cfg.food + 35)
        addXp(5)
    }

    func addXp(_ n: Int) {
        if demo || featDemo { return }
        let before = Cfg.level
        Cfg.xp += n
        spawn(pText, 0, -15 - hatH, 0, -4, 1.5, "+\(n) XP", 2.3, Ink.yellow)
        if Cfg.level > before { levelUp() }
        Cfg.save()
    }

    func levelUp() {
        confetti()
        announce(levelText(Cfg.level), 5)
    }

    func confetti() {
        for _ in 0..<26 {
            spawn(pCrumb, -10 + R() * 20, -12 - R() * 8, (R() - 0.5) * 22, -6 - R() * 12, 1.2 + R() * 0.8, "", 0, pal())
        }
    }

    // "Level 3!" plus what that level unlocks.
    func levelText(_ lv: Int) -> String {
        var news: [String] = []
        let al = Cfg.lang == "de" ? Pet.actLabelsDe : Pet.actLabelsEn
        for i in 0..<Pet.actNames.count where Pet.actLevel(Pet.actNames[i]) == lv { news.append(al[i]) }
        for i in 0..<Cfg.colLevel.count where Cfg.colLevel[i] == lv { news.append(Cfg.colLabels[i]) }
        for i in 0..<Cfg.hatLevel.count where Cfg.hatLevel[i] == lv { news.append(Cfg.hatLabels[i]) }
        var text = "Level \(lv)!"
        if !news.isEmpty { text += "\n" + T("Neu: ", "New: ") + news.joined(separator: ", ") }
        return text
    }

    var hatH: Double {
        switch Cfg.hat {
        case "cap": return 5
        case "party": return 7
        case "phones": return 2
        case "tophat": return 6
        case "crown": return 5
        default: return 0
        }
    }

    func doAct(_ name: String) {
        if dragging { return }
        set(name)
    }

    // MARK: Admin area

    func setXp(_ xp: Int) {
        endFeatureDemo()
        let before = Cfg.level
        Cfg.xp = max(0, xp)
        Cfg.save()
        if Cfg.level > before { levelUp() }
    }

    func setFood(_ food: Double) {
        endFeatureDemo()
        Cfg.food = food
        hungerNag = 0 // if he is hungry now, he says so right away
        Cfg.save()
    }

    // Shows the newer features one after the other: outfits, hunger, feeding, level-up,
    // dancing, landing on a window. Works on copies - XP, hunger and outfit are restored afterwards.
    func startFeatureDemo() {
        if featDemo || dragging { return }
        featDemo = true
        fdStep = 0
        fdT = 0.8
        fdMusic = false
        fdXp = Cfg.xp
        fdFood = Cfg.food
        fdHat = Cfg.hat
        Cfg.hat = "none"
        hungerShow = 0
        bubbleT = 0
        set("wave")
        dur = 99
    }

    func endFeatureDemo() {
        if !featDemo { return }
        featDemo = false
        fdMusic = false
        Cfg.xp = fdXp
        Cfg.food = fdFood
        Cfg.hat = fdHat
    }

    func featureDemo(_ dt: Double) {
        if dragging { return }
        fdT -= dt
        if fdT > 0 { return }
        let step = fdStep
        fdStep += 1
        if step < 5 {
            // try on every outfit
            Cfg.hat = Cfg.hatVals[step + 1]
            for _ in 0..<8 {
                spawn(pCrumb, -8 + R() * 16, -13 - R() * 5, (R() - 0.5) * 12, -3 - R() * 6, 0.7, "", 0, pal())
            }
            t = 0
            fdT = 1.4
        } else if step == 5 {
            // hungry: the cookie bubble
            Cfg.hat = "none"
            Cfg.food = 12
            set("idle")
            dur = 99
            hungerShow = 3.2
            bubbleAge = 0
            fdT = 3.2
        } else if step == 6 {
            hungerShow = 0
            set("eat")
            Cfg.food = 60
            spawn(pText, 0, -15, 0, -4, 1.5, "+5 XP", 2.3, Ink.yellow)
            fdT = 3.8
        } else if step == 7 {
            confetti()
            announce(levelText(Cfg.level + 1), 4)
            set("jump")
            fdT = 4.4
        } else if step == 8 {
            // headphones on, bounce to a made-up beat
            bubbleT = 0
            Cfg.hat = "phones"
            set("dance")
            musicDance = true
            fdMusic = true
            dur = 99
            fdT = 6
        } else if step == 9 {
            // drop onto the frontmost window that has room
            fdMusic = false
            Cfg.hat = "none"
            var found = false
            for i in 0..<plats.count where !found {
                let p = plats[i]
                let cx = max(workL + 12 * S, min(workR - 12 * S, (p.l + p.r) / 2))
                if !p.stand || cx < p.l + 8 * S || cx > p.r - 8 * S || covered(i, cx, p.t) { continue }
                found = true
                perch = 0
                x = cx
                y = max(workT + 13 * S, p.t - 45 * S)
                vx = 0
                vy = 0
                set("fall")
                air = true
            }
            if found {
                fdT = 3.5
            } else {
                set("idle")
                dur = 99
                announce(T("Für den Fenster-Teil bitte ein Fenster öffnen.", "Open a window for the window part."), 3.5)
                fdStep = 11
                fdT = 3.5
            }
        } else if step == 10 {
            // run off the nearer edge and fall down
            for p in plats where p.id == perch {
                set("run")
                tx = max(workL + 12 * S, min(workR - 12 * S, x - p.l < p.r - x ? p.l - 10 * S : p.r + 10 * S))
                break
            }
            fdT = 6
        } else {
            endFeatureDemo()
            if !air { set("idle") }
        }
    }

    // MARK: Logic

    func R() -> Double { return Double.random(in: 0..<1) }
    func pick(_ a: [String]) -> String { return a[Int.random(in: 0..<a.count)] }
    func pick(_ a: [[String]]) -> String { return pick(a[Cfg.lang == "de" ? 0 : 1]) }
    func pal() -> NSColor { return Ink.palette[Int.random(in: 0..<Ink.palette.count)] }
    func snap(_ v: Double) -> Double { return (v * scale).rounded() / scale }

    func randX() -> Double {
        var lo = workL + 12 * S, hi = workR - 12 * S
        for p in plats where p.id == perch {
            // now and then he strolls off the edge and drops down
            if R() < 0.2 { return max(lo, min(hi, R() < 0.5 ? p.l - 10 * S : p.r + 10 * S)) }
            lo = max(lo, p.l + 8 * S)
            hi = min(hi, p.r - 8 * S)
            break
        }
        return hi > lo ? lo + R() * (hi - lo) : x
    }

    func say(_ text: String, _ secs: Double) {
        if !Cfg.talk { return }
        announce(text, secs)
    }

    // Like say, but also shown when speech bubbles are switched off (level-ups).
    func announce(_ text: String, _ secs: Double) {
        bubbleText = text
        bubbleT = secs
        bubbleAge = 0
    }

    func spawn(_ kind: Int, _ px: Double, _ py: Double, _ pvx: Double, _ pvy: Double, _ life: Double, _ text: String, _ size: Double, _ color: NSColor) {
        var p = Particle()
        p.kind = kind
        p.x = px
        p.y = py
        p.vx = pvx
        p.vy = pvy
        p.life = life
        p.max = life
        p.text = text
        p.size = size
        p.color = color
        parts.append(p)
    }

    func every(_ interval: Double, _ dt: Double) -> Bool {
        spawnT -= dt
        if spawnT > 0 { return false }
        spawnT = interval
        return true
    }

    func launch(_ cells: Double) {
        vy = -(2 * 260 * S * cells * S).squareRoot()
        air = true
    }

    func moveTo(_ target: Double, _ speed: Double, _ dt: Double) -> Bool {
        let d = target - x
        if abs(d) <= speed * dt {
            x = target
            return true
        }
        dir = d > 0 ? 1 : -1
        x += Double(dir) * speed * dt
        moving = true
        return false
    }

    func set(_ s: String) {
        st = s
        t = 0
        phase = 0
        rot = 0
        spawnT = 0
        hopT = 0
        musicDance = false
        side = x < workL + (workR - workL) / 2 ? -1 : 1
        switch s {
        case "idle":
            dur = 4 + R() * 8
            if R() < 0.12 && bubbleT <= 0 { say(pick(Pet.idleLines), 3.5) }
        case "walk", "run": tx = randX()
        case "sleep": dur = 14 + R() * 14
        case "code":
            dur = 10 + R() * 10
            typed = false
            if R() < 0.6 { say(pick(Pet.codeLines), 3) }
        case "coffee": dur = 8 + R() * 5
        case "read": dur = 10 + R() * 6
        case "dance": dur = 6 + R() * 4
        case "jump":
            hops = 3
            launch(12)
        case "flip":
            launch(18)
            say(T("Hepp!", "Hup!"), 1.2)
        case "wave":
            dur = 3
            say(T("Hallo!", "Hello!"), 2.5)
        case "think":
            dur = 6
            say(". . .", 3.2)
        case "cool":
            dur = 8
            say(T("Läuft.", "Smooth."), 2.5)
        case "juggle": dur = 8
        case "balloon": dur = 4 + R() * 3
        case "stretch":
            dur = 2.5
            say(T("*gähn*", "*yawn*"), 2)
        case "chase": dur = 9
        case "eat": dur = 3.6
        case "pet": dur = 1.5
        case "drag": say(pick(Pet.dragLines), 2)
        case "fall": maxImpact = 0
        case "dizzy": dur = 2.5
        default: break
        }
        // keep the show moving: short pauses, nothing longer than 5 seconds
        if demo { dur = s == "idle" ? 1.2 : min(dur, 5) }
    }

    func weight(_ i: Int, _ night: Bool) -> Int {
        return Pet.actNames[i] == "sleep" && night ? Pet.actWeights[i] * 5 : Pet.actWeights[i]
    }

    func pickActivity() {
        let hr = Calendar.current.component(.hour, from: Date())
        let night = hr >= 23 || hr < 6
        var total = 0
        for i in 0..<Pet.actNames.count where Pet.actNames[i] != lastAct { total += weight(i, night) }
        if total <= 0 { return }
        var r = Int.random(in: 0..<total)
        for i in 0..<Pet.actNames.count where Pet.actNames[i] != lastAct {
            r -= weight(i, night)
            if r < 0 {
                lastAct = Pet.actNames[i]
                set(Pet.actNames[i])
                return
            }
        }
    }

    func nextDemo() {
        let a = Pet.demoScript[demoIdx % Pet.demoScript.count]
        demoIdx += 1
        if a == "pet" { petIt() } else { set(a) }
    }

    // Called 60 times a second; draws at 30 when nothing fast is going on.
    func tick() {
        let now = CACurrentMediaTime()
        let fast = dragging || pressed || air
        let want = fast ? 1.0 / 60 : st == "sleep" ? 1.0 / 20 : 1.0 / 30
        if now - last < want - 0.004 { return }
        let dt = min(0.1, now - last)
        last = now
        readScreen()
        readCursor()
        anim += dt
        if bubbleT > 0 { bubbleT -= dt }
        bubbleAge += dt
        blinkT -= dt
        if blinkT < -0.13 { blinkT = 1.5 + R() * 4 }
        logT -= dt
        if logT <= 0 && logPath != nil {
            logT = 1
            log((featDemo ? "demo\(fdStep) " : "") + "hat=\(Cfg.hat) \(st) x=\(Int(x)) y=\(Int(y)) air=\(air) windows=\(plats.count) level=\(Cfg.level) food=\(Int(Cfg.food))")
        }
        readInput(dt)
        updateNeeds(dt)
        beat = featDemo && fdMusic ? 0.12 + 0.2 * abs(sin(anim * 3.5)) : 0
        scanT -= dt
        if scanT <= 0 {
            scanT = air || dragging ? 0.08 : 0.25
            scanWindows()
        }
        if featDemo && !menuOpen { featureDemo(dt) }
        if !menuOpen { updatePet(dt) }
        updateParticles(dt)
        place()
        needsDisplay = true
    }

    func calm() -> Bool {
        return !air && !dragging && !pressed && y >= ground - 0.5 && !Pet.busy.contains(st)
    }

    // Hunger grows slowly while the app runs; when it gets bad he asks for food.
    func updateNeeds(_ dt: Double) {
        petXpT -= dt
        hungerShow -= dt
        if demo || featDemo { return }
        Cfg.food = max(0, Cfg.food - dt * 100 / 9000) // full -> empty in about 2.5 hours
        saveT -= dt
        if saveT <= 0 {
            saveT = 60
            Cfg.save()
        }
        if Cfg.food >= 30 {
            hungerNag = 5
            return
        }
        hungerNag -= dt
        if hungerNag > 0 || bubbleT > 0 || dragging || air || st == "sleep" || st == "eat" { return }
        hungerNag = Cfg.food < 10 ? 25 : 60
        hungerShow = 5
        bubbleAge = 0
        say(T("Ich hab Hunger!", "I'm hungry!"), 4)
    }

    func secondsSince(_ type: CGEventType) -> Double {
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    // Only counts THAT keys are being pressed - never which ones. Nothing is stored or sent.
    func readInput(_ dt: Double) {
        let n = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        let hits = n &- keyCount
        keyCount = n
        if demo || featDemo { return } // the script decides, not the keyboard
        typingT += dt
        tapT -= dt
        let idle = min(secondsSince(.keyDown), secondsSince(.mouseMoved), secondsSince(.leftMouseDown), secondsSince(.scrollWheel))
        let isCalm = calm()

        if hits > 0 && hits < 50 {
            typingT = 0
            tapT = 0.12
            tapArm = 1 - tapArm
            if st != "code" && isCalm { set("code") }
            if st == "code" {
                typed = true
                spawn(pText, -5 + R() * 10, -7, (R() - 0.5) * 3, -5, 1.2, pick(Pet.codeBits), 2.2, pal())
            }
        }
        // Nobody there -> fall asleep; back again -> wake up and wave
        let away = idle > 120
        if away && isCalm && st != "sleep" { set("sleep") }
        if wasAway && !away && st == "sleep" { set("wave") }
        wasAway = away
    }

    // MARK: Other windows as platforms

    // Collects the visible app windows, front to back.
    func scanWindows() {
        plats.removeAll(keepingCapacity: true)
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return }
        for w in list {
            // layer 0 = ordinary app windows (the Dock, menu bar and overlays live on other layers)
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let pid = w[kCGWindowOwnerPID as String] as? Int, pid == myPid { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: Any],
                  let bx = b["X"] as? Double, let by = b["Y"] as? Double,
                  let bw = b["Width"] as? Double, let bh = b["Height"] as? Double else { continue }
            if bw < 2 || bh < 2 { continue }
            var p = Plat()
            p.id = w[kCGWindowNumber as String] as? Int ?? 0
            p.l = bx
            p.t = by
            p.r = bx + bw
            p.b = by + bh
            // good to stand on: a window with room above it for Clawd
            p.stand = bw >= 30 * S && p.t - 13 * S >= workT && p.t <= workB - 6 * S
            plats.append(p)
        }
    }

    // Is the spot (px, top edge) of window number i hidden behind a window in front of it?
    func covered(_ i: Int, _ px: Double, _ py: Double) -> Bool {
        for j in 0..<i {
            let q = plats[j]
            if px >= q.l && px <= q.r && py + 1 >= q.t && py + 1 <= q.b { return true }
        }
        return false
    }

    // What he is standing on right now: a window's top edge or the bottom of the work area.
    var ground: Double {
        if perch != 0 {
            for p in plats where p.id == perch { return p.t }
        }
        return workB
    }

    func perchOk() -> Bool {
        for i in 0..<plats.count where plats[i].id == perch {
            let p = plats[i]
            return p.stand && abs(p.t - y) < 1.5 && x >= p.l + S && x <= p.r - S && !covered(i, x, p.t)
        }
        return false
    }

    // First surface he hits while dropping from y0 to y1.
    func findSurface(_ px: Double, _ y0: Double, _ y1: Double) -> (top: Double, id: Int)? {
        var top = Double.greatestFiniteMagnitude
        var id = 0
        if y1 >= workB { top = workB }
        for i in 0..<plats.count {
            let p = plats[i]
            if !p.stand || p.t < y0 - 0.5 || p.t > y1 || p.t >= top { continue }
            if px < p.l + 2 * S || px > p.r - 2 * S || covered(i, px, p.t) { continue }
            top = p.t
            id = p.id
        }
        return top == Double.greatestFiniteMagnitude ? nil : (top, id)
    }

    func place() {
        winLeft = snap(x - W / 2)
        let top = snap(y - (Pet.CH - 1) * S)
        window?.setFrameOrigin(NSPoint(x: winLeft, y: screenH - top - H))
    }

    func updateParticles(_ dt: Double) {
        var i = parts.count - 1
        while i >= 0 {
            parts[i].life -= dt
            if parts[i].life <= 0 {
                parts.remove(at: i)
            } else {
                if parts[i].kind == pCrumb { parts[i].vy += 30 * dt }
                parts[i].x += parts[i].vx * dt
                parts[i].y += parts[i].vy * dt
            }
            i -= 1
        }
    }

    func physics(_ dt: Double) {
        let y0 = y
        vy += 260 * S * dt
        x += vx * dt
        y += vy * dt
        let minX = workL + 9 * S, maxX = workR - 9 * S
        if x < minX {
            x = minX
            vx = -vx * 0.6
        }
        if x > maxX {
            x = maxX
            vx = -vx * 0.6
        }
        if y < workT + 12 * S {
            y = workT + 12 * S
            vy = abs(vy) * 0.5
        }
        if vy < 0 { return } // still on the way up

        guard let hit = findSurface(x, y0, y) else { return }
        y = hit.top
        if st == "fall" && vy > 60 * S {
            if vy > maxImpact { maxImpact = vy }
            vy = -vy * 0.4
            vx *= 0.7
            return
        }
        perch = hit.id
        log("landed on " + (hit.id == 0 ? "ground" : "window \(hit.id)") + " at y=\(Int(y))")
        vx = 0
        vy = 0
        air = false
        if st == "jump" {
            hops -= 1
            if hops > 0 { launch(12) } else { set("idle") }
        } else if st == "flip" {
            set("idle")
        } else if st == "fall" {
            if maxImpact > 300 * S {
                set("dizzy")
                say(T("Mir ist schwindelig...", "I'm dizzy..."), 2.5)
            } else {
                set("idle")
            }
        }
    }

    func updatePet(_ dt: Double) {
        t += dt
        moving = false

        if pressed && !dragging {
            let dx = curX - pressX, dy = curY - pressY
            if dx * dx + dy * dy > 25 {
                dragging = true
                air = false
                perch = 0
                set("drag")
            }
        }
        if dragging {
            let nx = curX + grabX, ny = curY + grabY
            if dt > 0 {
                thvx = thvx * 0.6 + (nx - x) / dt * 0.4
                thvy = thvy * 0.6 + (ny - y) / dt * 0.4
            }
            x = max(workL + 9 * S, min(workR - 9 * S, nx))
            y = max(workT + 12 * S, min(workB, ny))
            return
        }

        let floating = st == "climb" || st == "balloon"
        // The window under him was moved, closed or covered: down he goes
        if perch != 0 && !air && !perchOk() {
            perch = 0
            log("lost the window under him")
            if !floating {
                set("fall")
                air = true
            }
        }
        let gnd = ground
        if !air && !floating && y < gnd - 0.5 { air = true }
        if air { physics(dt) }

        switch st {
        case "idle":
            if t > dur && !air {
                if featDemo {
                } else if demo {
                    nextDemo()
                } else {
                    pickActivity()
                }
            }
        case "walk":
            if moveTo(tx, 12 * S, dt) { set("idle") }
        case "run":
            if moveTo(tx, 45 * S, dt) { set("idle") }
        case "sleep":
            if every(1.3, dt) { spawn(pText, 6, -9, 2.2, -3.5, 2.4, "z", 2.2, pal()) }
            if t > dur && !wasAway {
                set("idle")
                say(T("Gut geschlafen!", "Slept well!"), 2.5)
            }
        case "code":
            if typed {
                if typingT > 2.5 { set("idle") }
            } else {
                if every(0.7, dt) { spawn(pText, -5 + R() * 10, -7, (R() - 0.5) * 2, -4, 1.8, pick(Pet.codeBits), 2.2, pal()) }
                if t > dur { set("idle") }
            }
        case "coffee":
            if t.truncatingRemainder(dividingBy: 4) < 3 && every(0.5, dt) {
                spawn(pSteam, 10.5 + R() * 1.5, -10, R() - 0.5, -2.5, 1.2, "", 0, Ink.steam)
            }
            if t > dur {
                set("idle")
                say(T("Ahh, Kaffee.", "Ahh, coffee."), 2)
            }
        case "dance":
            if every(0.55, dt) { spawn(pText, -9 + R() * 18, -11, (R() - 0.5) * 3, -4, 1.6, R() < 0.5 ? "♪" : "♫", 3, pal()) }
            if R() < 0.15 { spawn(pCrumb, -14 + R() * 28, -22, (R() - 0.5) * 4, 2, 1.4, "", 0, pal()) }
            if t > dur { set("idle") }
        case "flip":
            let total = 2 * (2 * 260 * S * 18 * S).squareRoot() / (260 * S)
            rot = 360 * min(1, t / total) * Double(dir)
        case "think":
            if phase == 0 && t > 3.5 {
                phase = 1
                say(pick(Pet.ideaLines), 2.3)
            }
            if t > dur { set("idle") }
        case "climb":
            if phase == 0 {
                if moveTo(side < 0 ? workL + 6 * S : workR - 6 * S, 14 * S, dt) {
                    phase = 1
                    climbTop = gnd - (workB - workT) * (0.3 + R() * 0.4)
                }
            } else if phase == 1 {
                rot = side < 0 ? 90 : -90
                moving = true
                y -= 9 * S * dt
                if y <= climbTop {
                    phase = 2
                    t = 0
                }
            } else {
                rot = side < 0 ? 90 : -90
                if t > 2.5 {
                    let sd = side
                    set("fall")
                    air = true
                    vx = -Double(sd) * 25 * S
                    vy = -20 * S
                    say(T("Huiii!", "Wheee!"), 1.5)
                }
            }
        case "chase":
            let target = max(workL + 9 * S, min(workR - 9 * S, curX))
            hopT -= dt
            if abs(target - x) > 12 * S {
                _ = moveTo(target, 40 * S, dt)
            } else if !air && hopT <= 0 {
                launch(4)
                hopT = 0.9
            }
            if t > dur && !air {
                set("idle")
                say(T("Hab dich!", "Gotcha!"), 2)
            }
        case "balloon":
            y -= 12 * S * dt
            x += sin(t * 1.3) * 8 * S * dt
            if t > dur || y < workT + 45 * S {
                for _ in 0..<9 { spawn(pCrumb, 8, -20, (R() - 0.5) * 30, -R() * 14, 0.8, "", 0, Ink.red) }
                set("fall")
                air = true
                say(T("Peng!", "Pop!"), 1.5)
            }
        case "stretch":
            if t > dur { set(R() < 0.5 && !demo ? "sleep" : "idle") }
        case "eat":
            if every(0.9, dt) && t > 0.5 {
                for _ in 0..<4 { spawn(pCrumb, 10, -9, (R() - 0.5) * 8, -R() * 5, 0.7, "", 0, Ink.cookie) }
            }
            if t > dur {
                set("idle")
                say(T("Lecker!", "Yummy!"), 2)
            }
        case "read", "wave", "cool", "juggle", "pet", "dizzy":
            if t > dur { set("idle") }
        default: break
        }

        x = max(workL + 6 * S, min(workR - 6 * S, x))
        if !air && st != "climb" && st != "balloon" && y > gnd { y = gnd }
    }

    // MARK: Drawing

    var ctx: CGContext!

    func C(_ color: NSColor, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double) {
        let x0 = snap(ox + cx * S), y0 = snap(oy + cy * S), x1 = snap(ox + (cx + w) * S), y1 = snap(oy + (cy + h) * S)
        if x1 <= x0 || y1 <= y0 { return }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }

    func bmp(_ rows: [String], _ cx: Double, _ cy: Double, _ u: Double, _ main: NSColor, _ alt: NSColor, _ maxCols: Int) {
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() where c < maxCols && ch != "." {
                C(ch == "X" ? main : alt, cx + Double(c) * u, cy + Double(r) * u, u, u)
            }
        }
    }

    func txt(_ s: String, _ cx: Double, _ cy: Double, _ sizeCells: Double, _ color: NSColor) {
        let size = CGFloat(max(7, sizeCells * S))
        let font = NSFont(name: "Menlo-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = s as NSString
        let sz = str.size(withAttributes: attrs)
        ctx.setShouldAntialias(true)
        str.draw(at: NSPoint(x: ox + cx * S - Double(sz.width) / 2, y: oy + cy * S - Double(sz.height) / 2), withAttributes: attrs)
        ctx.setShouldAntialias(false)
    }

    // ex = left edge of the 1-cell-wide eye
    func eye(_ mode: Int, _ ex: Double, _ ey: Double) {
        let k = Ink.ink
        switch mode {
        case eyeOpen: C(k, ex, ey, 1, 2)
        case eyeClosed: C(k, ex - 0.5, ey + 1, 2, 0.7)
        case eyeHappy:
            C(k, ex - 1, ey + 1, 1, 1)
            C(k, ex, ey, 1, 1)
            C(k, ex + 1, ey + 1, 1, 1)
        case eyeWide:
            C(k, ex - 0.5, ey - 0.5, 2, 2.5)
            C(Ink.white, ex - 0.5, ey - 0.5, 1, 1)
        default:
            C(k, ex - 1, ey - 0.5, 1, 1)
            C(k, ex + 1, ey - 0.5, 1, 1)
            C(k, ex, ey + 0.5, 1, 1)
            C(k, ex - 1, ey + 1.5, 1, 1)
            C(k, ex + 1, ey + 1.5, 1, 1)
        }
    }

    // Permanent outfit, sitting on top of the head (top = upper edge of the body).
    func drawHat(_ top: Double) {
        switch Cfg.hat {
        case "cap":
            C(Ink.white, -1, top - 5, 2, 1)
            C(Ink.hatBlue, -3, top - 4, 6, 1)
            C(Ink.hatBlue, -5, top - 3, 10, 1)
            C(Ink.hatBlue, -6, top - 2, 12, 1)
            C(Ink.white, -6.5, top - 1, 13, 1.2)
        case "party":
            C(Ink.yellow, -0.5, top - 7, 1, 1)
            C(Ink.pink, -0.5, top - 6, 1, 1)
            C(Ink.blue, -1, top - 5, 2, 1)
            C(Ink.pink, -1.5, top - 4, 3, 1)
            C(Ink.blue, -2, top - 3, 4, 1)
            C(Ink.pink, -2.5, top - 2, 5, 1)
            C(Ink.blue, -3, top - 1, 6, 1)
        case "phones":
            C(Ink.ink, -6.5, top - 1.6, 13, 1.1)
            C(Ink.ink, -8, top - 1, 1.5, 1.6)
            C(Ink.ink, 6.5, top - 1, 1.5, 1.6)
            C(Ink.ink, -8.6, top + 0.5, 1.6, 2.5)
            C(Ink.ink, 7, top + 0.5, 1.6, 2.5)
            C(Ink.teal, -8.6, top + 1, 0.6, 1.5)
            C(Ink.teal, 8, top + 1, 0.6, 1.5)
        case "tophat":
            C(Ink.ink, -3.5, top - 6, 7, 5)
            C(Ink.red, -3.5, top - 2.2, 7, 1.2)
            C(Ink.ink, -5.5, top - 1, 11, 1)
        case "crown":
            C(Ink.crownGold, -4.5, top - 4, 1.5, 2)
            C(Ink.crownGold, -0.75, top - 4.6, 1.5, 2.6)
            C(Ink.crownGold, 3, top - 4, 1.5, 2)
            C(Ink.crownGold, -4.5, top - 2, 9, 2)
            C(Ink.red, -0.5, top - 1.5, 1, 1)
            C(Ink.blue, -3.3, top - 1.5, 1, 1)
            C(Ink.blue, 2.3, top - 1.5, 1, 1)
        default: break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        if let w = window { scale = Double(w.backingScaleFactor) }
        render(c)
    }

    // Draws Clawd, his props, particles and the bubble into a top-left-origin context.
    func render(_ c: CGContext) {
        ctx = c
        ctx.setShouldAntialias(false)

        var sway = 0.0, lift = 0.0, bob = 0.0, aL = 0.0, aR = 0.0, tall = 0.0
        var eyeMode = eyeOpen, lx = 0.0, ly = 0.0
        var sit = false, dangle = false, glasses = false
        let fastLegs = st == "run" || st == "chase"
        let frame = Int(anim * (fastLegs ? 12 : 6)) % 2
        let beatStep = Int(anim * 6) % 2

        if abs(curX - x) > 8 * S { lx = curX > x ? 1 : -1 }
        if curY < y - 30 * S { ly = -1 }
        bob = moving ? (frame == 0 ? 0 : -0.6) : sin(anim * 2.2) * 0.25
        if air {
            bob = 0
            if vy < 0 {
                aL = -2
                aR = -2
            }
        }

        switch st {
        case "sleep":
            sit = true
            eyeMode = eyeClosed
            lx = 0
            ly = 0
            bob = (sin(anim * 1.3) + 1) * 0.3
        case "code":
            lx = 0
            ly = 1
            if !typed {
                aL = Double(Int(anim * 9) % 2)
                aR = 1 - aL
            } else if tapT > 0 {
                if tapArm == 0 { aL = 1 } else { aR = 1 }
            }
        case "coffee":
            if t.truncatingRemainder(dividingBy: 4) >= 3 {
                aR = -2
                eyeMode = eyeClosed
            }
        case "read":
            ly = 1
            lx = Double(Int(anim * 1.5) % 3 - 1)
            aL = 2
            aR = 2
        case "dance":
            // in the feature demo the bounce follows a beat
            lift = -abs(sin(anim * 6)) * 1.5 * (musicDance ? 0.45 + min(1.2, beat * 4) : 1)
            sway = sin(anim * 3) * 1.5
            if sin(anim * 3) > 0 { aL = -3 } else { aR = -3 }
            eyeMode = eyeHappy
            lx = 0
            ly = 0
        case "jump", "flip":
            eyeMode = eyeHappy
            lx = 0
            ly = 0
        case "wave":
            aR = -3 + Double(beatStep)
            eyeMode = eyeHappy
            lx = 0
            ly = 0
        case "think":
            if phase == 0 {
                lx = 1
                ly = -1
                aR = -1
            } else {
                eyeMode = eyeHappy
                lx = 0
                ly = 0
                aL = -2
                aR = -2
            }
        case "cool":
            glasses = true
            lx = 0
            ly = 0
        case "climb":
            if phase > 0 {
                lx = 0
                ly = phase == 2 ? 1 : -1
            }
        case "juggle":
            lx = 0
            ly = -1
            aL = -Double(beatStep)
            aR = -Double(1 - beatStep)
        case "balloon":
            aR = -3
            ly = -1
            lx = 0
            dangle = true
            bob = 0
        case "stretch":
            aL = -3
            aR = -3
            eyeMode = eyeClosed
            tall = 1
            bob = 0
        case "eat":
            aR = -2
            if t.truncatingRemainder(dividingBy: 0.9) < 0.3 { eyeMode = eyeHappy }
            lx = 0
            ly = 0
        case "pet":
            eyeMode = eyeHappy
            lx = 0
            ly = 0
            lift = -abs(sin(t * 10)) * 1.0
        case "drag":
            eyeMode = eyeWide
            lx = 0
            ly = 0
            dangle = true
            aL = -2
            aR = -2
            bob = 0
        case "fall":
            eyeMode = eyeWide
            lx = 0
            ly = 0
            aL = -2
            aR = -2
        case "dizzy":
            eyeMode = eyeDizzy
            lx = 0
            ly = 0
            sway = sin(anim * 5) * 0.8
        case "chase":
            if !moving { eyeMode = eyeHappy }
        default: break
        }
        if blinkT < 0 && eyeMode == eyeOpen { eyeMode = eyeClosed }

        let baseX = W / 2, baseY = (Pet.CH - 1) * S
        ox = baseX + sway * S
        oy = baseY + lift * S
        let so = sit ? 2.0 : 0.0
        let bodyTop = -10 - tall + bob + so
        let bodyBot = sit ? 0 : -2 + bob
        let armY = -7 + bob + so

        ctx.saveGState()
        if rot != 0 {
            ctx.translateBy(x: ox, y: oy - 6 * S)
            ctx.rotate(by: rot * .pi / 180)
            ctx.translateBy(x: -ox, y: -(oy - 6 * S))
        }

        if st == "balloon" {
            C(Ink.cream, 7.85, -16, 0.3, 6 + bob)
            bmp(Pet.balloon, 4, -25, 1, Ink.red, Ink.white, 99)
        }

        if !sit {
            let legX = [-6.0, -4.0, 3.0, 5.0]
            for i in 0..<4 {
                var len = -bodyBot
                if dangle {
                    len = (i + Int(anim * 10)) % 2 == 0 ? 2 : 1.2
                } else if air {
                    len = 2
                } else if moving && i % 2 == frame {
                    len = 1
                }
                C(bodyColor, legX[i], bodyBot, 1, len)
            }
        }
        C(bodyColor, -7, bodyTop, 14, bodyBot - bodyTop)
        C(bodyColor, -9, armY + aL, 2, 2)
        C(bodyColor, 7, armY + aR, 2, 2)

        let eyeY = -8 - tall * 0.5 + bob + so + ly
        eye(eyeMode, -4 + lx, eyeY)
        eye(eyeMode, 3 + lx, eyeY)

        if glasses {
            let gy = -8.5 + bob
            C(Ink.ink, -7, gy, 14, 1)
            C(Ink.ink, -6, gy, 5, 3)
            C(Ink.ink, 1, gy, 5, 3)
            C(Ink.shine, -5, gy + 1, 1, 1)
            C(Ink.shine, 2, gy + 1, 1, 1)
        }

        drawHat(bodyTop)

        switch st {
        case "code":
            C(Ink.grey, -5, -5, 10, 4)
            C(Ink.palette[Int(anim * 3) % Ink.palette.count], -1, -4, 2, 2)
            C(Ink.greyDark, -6, -1, 12, 1)
        case "read":
            C(Ink.brown, -6, -5, 12, 4)
            C(Ink.brownDark, -0.5, -5, 1, 4)
            C(Ink.gold, -4.5, -4, 3, 1)
            C(Ink.gold, 1.5, -4, 3, 1)
        case "coffee":
            let cy = armY + aR - 2.5
            C(Ink.white, 9.5, cy, 3, 3)
            C(Ink.white, 12.5, cy + 1, 1, 1)
            C(Ink.brownDark, 9.5, cy, 3, 0.6)
        case "eat":
            bmp(Pet.cookieBmp, 9, armY + aR - 3.5, 1, Ink.cookie, Ink.brownDark, 4 - min(3, Int(t / 0.9)))
        case "juggle":
            let cols = [Ink.red, Ink.yellow, Ink.blue]
            for i in 0..<3 {
                let p = anim * 1.2 + Double(i) / 3.0
                let f = p - p.rounded(.down)
                let ltr = Int(p.rounded(.down)) % 2 == 0
                let bx = ltr ? -8 + 16 * f : 8 - 16 * f
                let by = -10 - 12 * 4 * f * (1 - f)
                C(cols[i], bx - 1, by - 1, 2, 2)
            }
        default: break
        }

        ctx.restoreGState()

        // Overlays (neither rotated nor swayed with the body)
        ox = baseX
        oy = baseY

        if st == "dizzy" {
            for i in 0..<3 {
                let a = anim * 4 + Double(i) * 2.094
                let sx = 7 * cos(a), sy = -12.5 + 1.5 * sin(a)
                C(Ink.yellow, sx - 0.5, sy - 1.5, 1, 3)
                C(Ink.yellow, sx - 1.5, sy - 0.5, 3, 1)
            }
        }

        for p in parts {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(min(1, p.life / (p.max * 0.4))))
            switch p.kind {
            case pText: txt(p.text, p.x, p.y, p.size * (1 + (1 - p.life / p.max) * 0.5), p.color)
            case pHeart: bmp(Pet.heart, p.x - 1.75, p.y - 1.5, 0.5, p.color, p.color, 99)
            default: C(p.color, p.x, p.y, 0.7, 0.7)
            }
            ctx.restoreGState()
        }

        bubbleSit = sit
        ctx.setShouldAntialias(true)
        if bubbleT > 0 && !bubbleText.isEmpty { drawBubble() } else { drawHunger() }
        ctx.setShouldAntialias(false)
    }

    func spring() -> Double {
        let k = min(1, bubbleAge / 0.3) - 1
        return 0.6 + 0.4 * (1 + 2.0 * k * k * k + 1.0 * k * k)
    }

    // Glass-style speech bubble: pops in with a little bounce, fades out.
    func drawBubble() {
        let dark = isDark
        let fontSize = CGFloat(max(12, 2.5 * S))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: dark ? NSColor.white : Ink.ink,
            .paragraphStyle: style]
        let str = NSAttributedString(string: bubbleText, attributes: attrs)
        let maxW = 34 * S
        let tb = str.boundingRect(with: NSSize(width: maxW, height: 2000), options: [.usesLineFragmentOrigin])
        let tw = Double(tb.width.rounded(.up)), th = Double(tb.height.rounded(.up))
        let padX = max(11, 2.2 * S), padY = max(6, 1.2 * S)
        let bw = tw + 2 * padX, bh = th + 2 * padY
        let mid = W / 2
        let tail = max(5, 1.1 * S)

        // clamp to the screen first, then to the window
        var bx = max(workL + bw / 2 + 6, min(workR - bw / 2 - 6, winLeft + mid)) - winLeft
        bx = max(bw / 2 + 6, min(W - bw / 2 - 6, bx))
        let by = (Pet.CH - 1) * S - (bubbleSit ? 11 : 13) * S - hatH * S - tail - 0.6 * S
        let r = CGRect(x: bx - bw / 2, y: by - bh, width: bw, height: bh)
        let rad = min(bh / 2, 15)
        let tailX = max(Double(r.minX) + rad + tail, min(Double(r.maxX) - rad - tail, mid))
        let s = spring()
        let alpha = min(1, bubbleAge / 0.1) * min(1, bubbleT / 0.25)

        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        ctx.translateBy(x: tailX, y: by + tail)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -tailX, y: -(by + tail))

        let path = CGMutablePath()
        path.addRoundedRect(in: r, cornerWidth: rad, cornerHeight: rad)
        path.move(to: CGPoint(x: tailX - tail, y: by - 1))
        path.addLine(to: CGPoint(x: tailX, y: by + tail))
        path.addLine(to: CGPoint(x: tailX + tail, y: by - 1))
        path.closeSubpath()

        let fill = dark ? hex("#EB26262A") : hex("#F5FFFFFF")
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        let rim = CGMutablePath()
        rim.addRoundedRect(in: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: rad - 0.5, cornerHeight: rad - 0.5)
        ctx.addPath(rim)
        ctx.setStrokeColor((dark ? NSColor.white.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.12)).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        str.draw(with: NSRect(x: bx - maxW / 2, y: Double(r.minY) + padY, width: maxW, height: th), options: [.usesLineFragmentOrigin])
        ctx.restoreGState()
    }

    // "I'm hungry": a small thought bubble with a cookie in it. Shown even when speech bubbles are off.
    func drawHunger() {
        if hungerShow <= 0 { return }
        let dark = isDark
        let fill = dark ? hex("#EB26262A") : hex("#F5FFFFFF")
        let mid = W / 2, r = max(14, 3.3 * S)
        let feet = (Pet.CH - 1) * S - (bubbleSit ? 11 : 13) * S - hatH * S
        let cy = feet - r - 2.2 * S
        let s = spring()
        let alpha = min(1, bubbleAge / 0.1) * min(1, hungerShow / 0.25)

        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        ctx.translateBy(x: mid, y: feet)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -mid, y: -feet)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: CGRect(x: mid - r, y: cy - r, width: 2 * r, height: 2 * r))
        ctx.restoreGState()
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: CGRect(x: mid - 0.5 * r - 0.5 * S, y: feet - 1.1 * S, width: S, height: S))
        ctx.fillEllipse(in: CGRect(x: mid - 0.3 * r - 0.8 * S, y: feet - 2.5 * S, width: 1.6 * S, height: 1.6 * S))

        ctx.setShouldAntialias(false)
        let u = (r * 0.3).rounded()
        for (row, line) in Pet.cookieBmp.enumerated() {
            for (col, ch) in line.enumerated() where ch != "." {
                ctx.setFillColor((ch == "X" ? Ink.cookie : Ink.brownDark).cgColor)
                ctx.fill(CGRect(x: (mid - 2 * u).rounded() + Double(col) * u, y: (cy - 2 * u).rounded() + Double(row) * u, width: u, height: u))
            }
        }
        ctx.setShouldAntialias(true)
        ctx.restoreGState()
    }
}

// MARK: - Off-screen pictures (app icon, pose sheet for the README and for testing)

func makeBitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    let c = g.cgContext
    // top-left origin, like the flipped pet view
    c.translateBy(x: 0, y: CGFloat(h))
    c.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    draw(c)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePng(_ rep: NSBitmapImageRep, _ path: String) {
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

func drawLogo(_ c: CGContext, _ color: NSColor, _ x0: Double, _ y0: Double, _ cell: Double) {
    func cellRect(_ col: NSColor, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double) {
        c.setFillColor(col.cgColor)
        c.fill(CGRect(x: x0 + cx * cell, y: y0 + cy * cell, width: w * cell, height: h * cell))
    }
    c.setShouldAntialias(false)
    cellRect(color, 2, 0, 14, 8)
    cellRect(color, 0, 3, 18, 2)
    for lx in [3.0, 5.0, 12.0, 14.0] { cellRect(color, lx, 8, 1, 2) }
    cellRect(Ink.ink, 5, 2, 1, 2)
    cellRect(Ink.ink, 12, 2, 1, 2)
    c.setShouldAntialias(true)
}

func renderIcon(_ path: String) {
    let rep = makeBitmap(1024, 1024) { c in
        let r = CGRect(x: 100, y: 100, width: 824, height: 824)
        let bg = CGMutablePath()
        bg.addRoundedRect(in: r, cornerWidth: 185, cornerHeight: 185)
        c.addPath(bg)
        c.setFillColor(hex("#FAF9F5").cgColor)
        c.fillPath()
        drawLogo(c, hex(Cfg.orange), 512 - 9 * 34, 512 - 5 * 34, 34)
    }
    writePng(rep, path)
}

func renderSheet(_ path: String) {
    let states = ["idle", "walk", "sleep", "code", "coffee", "read", "dance", "wave", "cool", "juggle", "balloon", "stretch", "eat", "pet", "drag", "dizzy"]
    let cols = 4, rows = 4
    let pet = Pet(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
    pet.S = 5
    pet.scale = 1
    let tw = Int(pet.W), th = Int(pet.H)
    Cfg.talk = true
    let rep = makeBitmap(cols * tw, rows * th) { c in
        c.setFillColor(hex("#243447").cgColor)
        c.fill(CGRect(x: 0, y: 0, width: cols * tw, height: rows * th))
        for (i, s) in states.enumerated() {
            pet.parts.removeAll()
            pet.st = s
            pet.t = 3.1
            pet.anim = 1.3
            pet.phase = 0
            pet.rot = 0
            pet.blinkT = 1
            pet.moving = s == "walk"
            pet.bubbleT = 0
            pet.hungerShow = 0
            pet.x = 500
            pet.y = 500
            pet.curX = 500
            pet.curY = 500
            pet.winLeft = 500 - pet.W / 2
            pet.workL = 0
            pet.workR = 1000
            pet.workT = 0
            pet.workB = 1000
            if s == "sleep" { pet.spawn(pet.pText, 8, -12, 0, 0, 2, "z", 2.6, Ink.cream) }
            if s == "pet" {
                pet.spawn(pet.pHeart, -4, -13, 0, 0, 2, "", 0, Ink.red)
                pet.spawn(pet.pHeart, 4, -15, 0, 0, 2, "", 0, Ink.red)
            }
            if s == "code" {
                pet.typed = true
                pet.tapT = 0.1
                pet.spawn(pet.pText, -3, -13, 0, 0, 2, "{ }", 2.2, Ink.green)
                pet.spawn(pet.pText, 5, -16, 0, 0, 2, "</>", 2.2, Ink.yellow)
            }
            if s == "dance" {
                pet.spawn(pet.pText, -9, -15, 0, 0, 2, "♪", 3, Ink.pink)
                pet.spawn(pet.pText, 8, -17, 0, 0, 2, "♫", 3, Ink.blue)
            }
            if s == "idle" {
                pet.bubbleText = "Hi! I'm Clawd."
                pet.bubbleT = 3
                pet.bubbleAge = 1
            }
            if s == "stretch" {
                pet.hungerShow = 3
                pet.bubbleAge = 1
            }
            Cfg.hat = s == "idle" ? "crown" : s == "walk" ? "cap" : s == "dance" ? "phones" : s == "wave" ? "party" : s == "cool" ? "tophat" : "none"
            c.saveGState()
            c.translateBy(x: CGFloat((i % cols) * tw), y: CGFloat((i / cols) * th))
            pet.render(c)
            c.restoreGState()
        }
    }
    writePng(rep, path)
}

// MARK: - Menus

// Menu entry that runs a closure.
final class Item: NSMenuItem {
    var run: (() -> Void)?

    convenience init(_ title: String, checked: Bool = false, enabled: Bool = true, _ run: (() -> Void)? = nil) {
        self.init(title: title, action: nil, keyEquivalent: "")
        self.run = run
        if run != nil {
            target = self
            action = #selector(fire)
        }
        state = checked ? .on : .off
        isEnabled = enabled
    }

    @objc func fire() { run?() }
}

// Top of the menu: level, XP and how hungry he is.
final class StatusView: NSView {
    override var isFlipped: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        let lv = Cfg.level, lo = Cfg.xpFor(lv), hi = Cfg.xpFor(lv + 1)
        let left: CGFloat = 21, width = bounds.width - 42
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.labelColor]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        ("Level \(lv)" as NSString).draw(at: NSPoint(x: left, y: 6), withAttributes: title)
        let xpText = "\(Cfg.xp - lo) / \(hi - lo) XP" as NSString
        xpText.draw(at: NSPoint(x: left + width - xpText.size(withAttributes: small).width, y: 9), withAttributes: small)
        bar(NSRect(x: left, y: 28, width: width, height: 5), CGFloat(Cfg.xp - lo) / CGFloat(max(1, hi - lo)), hex(Cfg.orange))
        let mood = Cfg.food < 10 ? T("Sehr hungrig", "Starving") : Cfg.food < 30 ? T("Hungrig", "Hungry") : Cfg.food < 85 ? T("Zufrieden", "Content") : T("Satt", "Full")
        (mood as NSString).draw(at: NSPoint(x: left, y: 39), withAttributes: small)
        bar(NSRect(x: left, y: 57, width: width, height: 5), CGFloat(Cfg.food / 100), Cfg.food < 30 ? Ink.red : Ink.green)
    }

    func bar(_ r: NSRect, _ frac: CGFloat, _ color: NSColor) {
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: 2.5, yRadius: 2.5).fill()
        if frac <= 0 { return }
        color.setFill()
        var f = r
        f.size.width = max(5, r.width * min(1, frac))
        NSBezierPath(roundedRect: f, xRadius: 2.5, yRadius: 2.5).fill()
    }
}

// SHA-256 of the admin password. The password itself is not in the code.
let adminHash = "def311f008e18477bb13f6bf75a15739b90be4fa579c06815193d56ab08e6cd0"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: NSPanel!
    var pet: Pet!
    var statusItem: NSStatusItem!
    var timer: Timer?
    let args = CommandLine.arguments

    func applicationDidFinishLaunching(_ notification: Notification) {
        Cfg.load()
        let logging = args.contains("--log")
        if logging { Cfg.readOnly = true }
        if (Cfg.firstRun || args.contains("--setup")) && !args.contains("--skip-setup") && !logging {
            SetupWindow().runModal()
        }

        pet = Pet(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar            // always on top, above ordinary windows
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = pet

        pet.demo = args.contains("--demo")
        if let i = args.firstIndex(of: "--log"), i + 1 < args.count { pet.logPath = args[i + 1] }
        pet.onMenu = { [weak self] e in self?.showMenu(e) }
        pet.start()
        panel.orderFrontRegardless()
        if args.contains("--featdemo") {
            DispatcherQueueHelper.after(3) { [weak self] in self?.pet.startFeatureDemo() }
        }

        buildStatusItem()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.pet.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func applicationWillTerminate(_ notification: Notification) {
        pet?.endFeatureDemo()
        Cfg.save()
    }

    // MARK: Right-click menu (built fresh every time, so it is always up to date)

    func showMenu(_ e: NSEvent) {
        let m = buildMenu()
        m.delegate = self
        NSMenu.popUpContextMenu(m, with: e, for: pet)
    }

    func menuWillOpen(_ menu: NSMenu) { pet.menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { pet.menuOpen = false }

    // Submenu where exactly one entry is ticked. Entries above the current level are shown locked.
    func choice(_ title: String, _ labels: [String], _ selected: Int, _ need: [Int]?, _ pick: @escaping (Int) -> Void) -> NSMenuItem {
        let parent = Item(title)
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (i, label) in labels.enumerated() {
            let locked = need != nil && need![i] > Cfg.level && !pet.demo && i != selected
            sub.addItem(Item(locked ? label + "  ·  Level \(need![i])" : label, checked: i == selected, enabled: !locked) {
                pick(i)
                Cfg.save()
            })
        }
        parent.submenu = sub
        return parent
    }

    func buildMenu() -> NSMenu {
        let p = pet!
        let m = NSMenu()
        m.autoenablesItems = false

        let status = NSMenuItem()
        status.view = StatusView(frame: NSRect(x: 0, y: 0, width: 240, height: 70))
        m.addItem(status)
        m.addItem(.separator())
        m.addItem(Item(T("Streicheln", "Pet")) { p.petIt() })
        m.addItem(Item(T("Füttern", "Feed")) { p.feed() })
        m.addItem(Item(T("Komm her!", "Come here!")) { p.doAct("chase") })
        m.addItem(.separator())

        let acts = Item(T("Aktivität", "Activity"))
        let actMenu = NSMenu()
        actMenu.autoenablesItems = false
        let labels = Cfg.lang == "de" ? Pet.actLabelsDe : Pet.actLabelsEn
        for (i, name) in Pet.actNames.enumerated() {
            let need = Pet.actLevel(name)
            let locked = need > Cfg.level && !p.demo
            actMenu.addItem(Item(locked ? labels[i] + "  ·  Level \(need)" : labels[i], enabled: !locked) { p.doAct(name) })
        }
        acts.submenu = actMenu
        m.addItem(acts)

        m.addItem(choice(T("Outfit", "Outfit"), Cfg.hatLabels, Cfg.hatVals.firstIndex(of: Cfg.hat) ?? 0, Cfg.hatLevel) { i in Cfg.hat = Cfg.hatVals[i] })
        m.addItem(choice(T("Farbe", "Color"), Cfg.colLabels, Cfg.colVals.firstIndex(of: Cfg.color) ?? -1, Cfg.colLevel) { i in
            Cfg.color = Cfg.colVals[i]
            p.applyColor()
        })
        m.addItem(choice(T("Größe", "Size"), Cfg.sizeLabels, Cfg.sizeVals.firstIndex(of: Cfg.size) ?? -1, nil) { i in
            Cfg.size = Cfg.sizeVals[i]
            p.applyScale()
        })
        m.addItem(choice(T("Sprache", "Language"), ["Deutsch", "English"], Cfg.lang == "de" ? 0 : 1, nil) { i in
            Cfg.lang = i == 0 ? "de" : "en"
            p.bubbleT = 0
        })
        m.addItem(.separator())

        m.addItem(Item(T("Sprechblasen", "Speech bubbles"), checked: Cfg.talk) {
            Cfg.talk.toggle()
            if !Cfg.talk { p.bubbleT = 0 }
            Cfg.save()
        })
        if Cfg.canAutoStart {
            m.addItem(Item(T("Bei der Anmeldung starten", "Open at login"), checked: Cfg.autoStart) { Cfg.autoStart = !Cfg.autoStart })
        }
        m.addItem(Item(T("Einstellungen…", "Settings…")) { [weak self] in self?.openSetup() })
        m.addItem(Item(T("Demo-Modus", "Demo mode"), checked: p.demo) {
            p.demo.toggle()
            p.demoIdx = 0
            if p.demo && !p.dragging { p.set("idle") }
        })

        if !p.adminOn {
            m.addItem(Item("Admin…") { [weak self] in self?.askAdmin() })
        } else {
            let ad = Item("Admin")
            let am = NSMenu()
            am.addItem(Item(T("Funktions-Demo starten", "Run feature demo")) { p.startFeatureDemo() })
            am.addItem(.separator())
            am.addItem(Item("XP +5") { p.setXp(Cfg.xp + 5) })
            am.addItem(Item("XP +25") { p.setXp(Cfg.xp + 25) })
            am.addItem(Item("Level +1") { p.setXp(Cfg.xpFor(Cfg.level + 1)) })
            am.addItem(Item(T("XP auf 0", "Reset XP")) { p.setXp(0) })
            am.addItem(.separator())
            am.addItem(Item(T("Hunger: satt", "Hunger: full")) { p.setFood(100) })
            am.addItem(Item(T("Hunger: hungrig", "Hunger: hungry")) { p.setFood(25) })
            am.addItem(Item(T("Hunger: sehr hungrig", "Hunger: starving")) { p.setFood(5) })
            am.addItem(.separator())
            am.addItem(Item(T("Admin sperren", "Lock admin")) { p.adminOn = false })
            ad.submenu = am
            m.addItem(ad)
        }
        m.addItem(.separator())
        m.addItem(Item(T("Beenden", "Quit")) { NSApp.terminate(nil) })
        return m
    }

    func openSetup() {
        SetupWindow().runModal()
        pet.applyScale()
        pet.applyColor()
        if !Cfg.talk { pet.bubbleT = 0 }
    }

    func askAdmin() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = T("Admin-Bereich", "Admin area")
        alert.informativeText = T("Passwort eingeben", "Enter the password")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: T("Abbrechen", "Cancel"))
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() != .alertFirstButtonReturn { return }
        let digest = SHA256.hash(data: Data(field.stringValue.utf8))
        let hexString = digest.map { String(format: "%02x", $0) }.joined()
        if hexString == adminHash {
            pet.adminOn = true
        } else {
            NSSound.beep()
        }
    }

    // MARK: Menu bar icon

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            drawLogo(c, hex(Cfg.orange), 0, 4, 1)
            return true
        }
        statusItem.button?.image = img
        let m = NSMenu()
        m.addItem(Item(T("Zeigen / Verstecken", "Show / Hide")) { [weak self] in
            guard let s = self else { return }
            if s.panel.isVisible { s.panel.orderOut(nil) } else { s.panel.orderFrontRegardless() }
        })
        m.addItem(Item(T("Zurück in die Mitte", "Back to the centre")) { [weak self] in
            guard let s = self, let p = s.pet else { return }
            s.panel.orderFrontRegardless()
            p.x = p.workL + (p.workR - p.workL) / 2
            p.y = max(p.workT + 14 * p.S, p.workB - 150 * p.S)
            p.perch = 0
            p.set("fall")
            p.air = true
        })
        m.addItem(.separator())
        m.addItem(Item(T("Beenden", "Quit")) { NSApp.terminate(nil) })
        statusItem.menu = m
    }
}

enum DispatcherQueueHelper {
    static func after(_ secs: Double, _ run: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: run)
    }
}

// The pet's window never takes keyboard focus away from the app you are working in.
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

// MARK: - Welcome / settings window

final class Swatch: NSView {
    var color = NSColor.orange
    var selected = false
    var locked = false
    var onPick: (() -> Void)?

    override var intrinsicContentSize: NSSize { return NSSize(width: 34, height: 34) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        color.withAlphaComponent(locked ? 0.25 : 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        if selected {
            NSColor.labelColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.25, dy: 1.25), xRadius: 10, yRadius: 10)
            ring.lineWidth = 2.5
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !locked { onPick?() }
    }
}

final class LogoView: NSView {
    var color = hex(Cfg.orange)
    override var isFlipped: Bool { return true }
    override var intrinsicContentSize: NSSize { return NSSize(width: 108, height: 60) }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        drawLogo(c, color, 0, 0, 6)
    }
}

final class SetupWindow: NSObject, NSWindowDelegate {
    let win: NSWindow
    let logo = LogoView()
    let head = NSTextField(labelWithString: "")
    let sub = NSTextField(wrappingLabelWithString: "")
    let lLang = NSTextField(labelWithString: ""), lSize = NSTextField(labelWithString: ""), lColor = NSTextField(labelWithString: "")
    let langSeg = NSSegmentedControl(labels: ["Deutsch", "English"], trackingMode: .selectOne, target: nil, action: nil)
    let sizeSeg = NSSegmentedControl(labels: ["", "", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    let talk = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let auto = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let ok = NSButton(title: "", target: nil, action: nil)
    let hint = NSTextField(wrappingLabelWithString: "")
    var swatches: [Swatch] = []
    var color = Cfg.color

    override init() {
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 560), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        win.title = "Clawd"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self

        // frosted glass behind everything
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        win.contentView = glass

        head.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        head.alignment = .center
        sub.textColor = .secondaryLabelColor
        sub.alignment = .center
        for l in [lLang, lSize, lColor] { l.font = NSFont.systemFont(ofSize: 13, weight: .semibold) }
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        langSeg.selectedSegment = Cfg.lang == "de" ? 0 : 1
        langSeg.target = self
        langSeg.action = #selector(langChanged)
        langSeg.segmentDistribution = .fillEqually
        sizeSeg.selectedSegment = max(0, Cfg.sizeVals.firstIndex(of: Cfg.size) ?? 1)
        sizeSeg.segmentDistribution = .fillEqually

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 7
        for (i, v) in Cfg.colVals.enumerated() {
            let s = Swatch()
            s.color = hex(v)
            s.locked = Cfg.colLevel[i] > Cfg.level && v != Cfg.color
            s.toolTip = s.locked ? "Level \(Cfg.colLevel[i])" : nil
            s.onPick = { [weak self] in
                self?.color = v
                self?.mark()
            }
            swatches.append(s)
            row.addArrangedSubview(s)
        }

        talk.state = Cfg.talk ? .on : .off
        auto.state = Cfg.autoStart ? .on : .off
        auto.isHidden = !Cfg.canAutoStart

        ok.bezelStyle = .rounded
        ok.controlSize = .large
        ok.keyEquivalent = "\r"
        ok.bezelColor = hex(Cfg.orange)
        ok.target = self
        ok.action = #selector(done)

        // the stack lines everything up on the left; the logo gets a full-width box to sit centred in
        let logoBox = NSView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        logoBox.addSubview(logo)

        let stack = NSStackView(views: [logoBox, head, sub, lLang, langSeg, lSize, sizeSeg, lColor, row, talk, auto, ok, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 44, left: 30, bottom: 26, right: 30)
        stack.setCustomSpacing(14, after: logoBox)
        stack.setCustomSpacing(4, after: head)
        stack.setCustomSpacing(20, after: sub)
        stack.setCustomSpacing(16, after: langSeg)
        stack.setCustomSpacing(16, after: sizeSeg)
        stack.setCustomSpacing(20, after: row)
        stack.setCustomSpacing(22, after: auto)
        stack.setCustomSpacing(22, after: talk)
        stack.setCustomSpacing(8, after: talk)
        stack.setCustomSpacing(10, after: ok)
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            glass.widthAnchor.constraint(equalToConstant: 380),
            logoBox.widthAnchor.constraint(equalToConstant: 320),
            logoBox.heightAnchor.constraint(equalToConstant: 60),
            logo.centerXAnchor.constraint(equalTo: logoBox.centerXAnchor),
            logo.topAnchor.constraint(equalTo: logoBox.topAnchor),
            head.widthAnchor.constraint(equalToConstant: 320),
            sub.widthAnchor.constraint(equalToConstant: 320),
            langSeg.widthAnchor.constraint(equalToConstant: 320),
            sizeSeg.widthAnchor.constraint(equalToConstant: 320),
            ok.widthAnchor.constraint(equalToConstant: 320),
            hint.widthAnchor.constraint(equalToConstant: 320)
        ])

        retext()
        mark()
    }

    @objc func langChanged() {
        Cfg.lang = langSeg.selectedSegment == 0 ? "de" : "en"
        retext()
    }

    func retext() {
        head.stringValue = T("Hallo, ich bin Clawd!", "Hi, I'm Clawd!")
        sub.stringValue = T("Dein kleiner Mitbewohner für den Desktop. Wie hättest du mich gern?", "Your little desktop companion. How would you like me?")
        lLang.stringValue = T("Sprache", "Language")
        lSize.stringValue = T("Größe", "Size")
        lColor.stringValue = T("Farbe", "Color")
        for (i, l) in Cfg.sizeLabels.enumerated() { sizeSeg.setLabel(l, forSegment: i) }
        talk.title = T("Sprechblasen anzeigen", "Show speech bubbles")
        auto.title = T("Bei der Anmeldung starten", "Open at login")
        ok.title = T("Los geht's!", "Let's go!")
        hint.stringValue = T("Alles lässt sich später per Rechtsklick auf Clawd ändern.", "You can change everything later by right-clicking Clawd.")
    }

    // Highlight the chosen swatch and redraw the little Clawd in that colour.
    func mark() {
        for (i, s) in swatches.enumerated() {
            s.selected = Cfg.colVals[i] == color
            s.needsDisplay = true
        }
        logo.color = hex(color)
        logo.needsDisplay = true
    }

    @objc func done() { win.close() }

    func windowWillClose(_ notification: Notification) {
        Cfg.size = Cfg.sizeVals[max(0, min(Cfg.sizeVals.count - 1, sizeSeg.selectedSegment))]
        Cfg.color = color
        Cfg.talk = talk.state == .on
        Cfg.save()
        if Cfg.canAutoStart && (auto.state == .on) != Cfg.autoStart { Cfg.autoStart = auto.state == .on }
        NSApp.stopModal()
    }

    func runModal() {
        // always centred on the main screen
        if let scr = NSScreen.screens.first {
            win.layoutIfNeeded()
            let v = scr.visibleFrame, s = win.frame.size
            win.setFrameOrigin(NSPoint(x: v.midX - s.width / 2, y: v.midY - s.height / 2))
        }
        win.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            win.animator().alphaValue = 1
        }
        NSApp.runModal(for: win)
    }
}

// MARK: - Entry point

let cli = CommandLine.arguments
if let i = cli.firstIndex(of: "--icon"), i + 1 < cli.count {
    renderIcon(cli[i + 1])
    exit(0)
}
if let i = cli.firstIndex(of: "--sheet"), i + 1 < cli.count {
    _ = NSApplication.shared
    renderSheet(cli[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
