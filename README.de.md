<h1 align="center">Clawd Desktop Pet</h1>

<p align="center">
  <a href="README.md">English</a> · <b>Deutsch</b>
</p>

<p align="center">
  Ein kleiner Pixel-Mitbewohner, der auf deiner Windows-Taskleiste lebt.<br>
  Er läuft herum, schläft, trinkt Kaffee – und tippt mit, wenn du tippst.
</p>

<p align="center">
  <img src="docs/poses.png" alt="Clawd in sechzehn verschiedenen Posen" width="720">
</p>

> **Inoffizielles Fan-Projekt.** Dieses Projekt steht in keiner Verbindung zu Anthropic und wird nicht von Anthropic unterstützt. „Claude“ und das Clawd-Maskottchen gehören Anthropic.

## Was er kann

**Er beschäftigt sich selbst**

- Spaziert über die Taskleiste, hüpft, tanzt, winkt und streckt sich
- Schläft (nachts öfter), trinkt Kaffee, liest ein Buch, setzt die Sonnenbrille auf
- Folgt deinem Mauszeiger mit den Augen und blinzelt

**Er reagiert auf dich**

- **Du tippst → er tippt.** Clawd holt einen Laptop raus und drückt für jeden deiner Tastendrücke eine Taste
- **Du bist 2 Minuten weg → er schläft ein**
- **Du kommst zurück → er wacht auf und winkt**

**Du kannst mit ihm spielen**

| Aktion | Was passiert |
| --- | --- |
| Klick | Streicheln (Herzchen!) – oder aufwecken |
| Doppelklick | Salto |
| Ziehen und loslassen | Hochheben und werfen – er prallt ab und wird nach hartem Aufprall schwindelig |
| Rechtsklick | Menü: Füttern, weitere Aktivitäten, Größe, Farbe, Sprache, Sprechblasen, Autostart |
| Symbol neben der Uhr | Zeigen / Verstecken, zurück in die Mitte, Beenden |

Im Rechtsklick-Menü warten noch mehr Tricks: Jonglieren, eine Ballonfahrt, den Bildschirmrand hochklettern, die Maus jagen.

## Loslegen

**Download:** `ClawdPet.exe` von der Seite [Releases](../../releases) laden und doppelklicken. Kein Installer, keine Abhängigkeiten – es ist eine einzige kleine Datei.

Beim ersten Start fragt ein Willkommensfenster nach **Sprache (Deutsch / English)**, Größe und Farbe:

<p align="center">
  <img src="docs/setup-de.png" alt="Willkommensfenster mit Sprache, Größe und Farbe" width="320">
</p>

Alles lässt sich später per Rechtsklick auf Clawd ändern.

> Windows SmartScreen warnt eventuell vor einem unbekannten Herausgeber, weil die Datei nicht signiert ist. Wähle „Weitere Informationen“ → „Trotzdem ausführen“ oder baue die App selbst aus dem Quellcode.

## Selbst bauen

Es muss nichts installiert werden – das Skript nutzt den C#-Compiler, der in Windows enthalten ist (.NET Framework 4.x):

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
.\ClawdPet.exe
```

Die ganze App steckt in einer Datei: [`ClawdPet.cs`](ClawdPet.cs).

## Demo-Modus

Du willst ein Video aufnehmen? Rechtsklick auf Clawd → **Demo-Modus** (oder Start mit `ClawdPet.exe --demo`). Dann spielt er alle 17 Aktivitäten nacheinander in fester Reihenfolge ab, jeweils ein paar Sekunden, und ignoriert dabei deine Tastatur.

## Datenschutz

Zum Mittippen fragt die App Windows, *ob* gerade eine Taste gedrückt ist (`GetAsyncKeyState`). *Welche* Taste es ist, wird nie ausgewertet, und nichts wird gespeichert oder gesendet – die App nutzt das Netzwerk überhaupt nicht. Manche Virenscanner stufen so eine Abfrage trotzdem als verdächtig ein.

Die Einstellungen liegen in `%AppData%\ClawdPet\settings.txt`.

## Gut zu wissen

- Windows 10 / 11
- Clawd bleibt auf dem Hauptmonitor
- Braucht im Betrieb ein paar Prozent eines CPU-Kerns

## Mitmachen

Ideen, Fehlerberichte und Pull Requests sind willkommen – besonders neue Aktivitäten und weitere Sprachen.

## Lizenz

[MIT](LICENSE) für den Code. Die Figur Clawd und der Name Claude bleiben Eigentum von Anthropic.
