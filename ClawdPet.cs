// Clawd Desktop Pet - a tiny pixel companion that lives on your Windows desktop.
// Unofficial fan project, not affiliated with Anthropic.
// Build: build.ps1 (uses the C# compiler that ships with Windows, nothing to install)

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using WF = System.Windows.Forms;
using SD = System.Drawing;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        // Developer helpers: render the pose sheet / the setup dialog into a PNG.
        if (args.Length == 2 && args[0] == "--sheet")
        {
            PetWindow.RenderSheet(args[1]);
            return;
        }
        if (args.Length == 3 && args[0] == "--setup-shot")
        {
            Cfg.Lang = args[2] == "de" ? "de" : "en";
            SetupWindow.RenderShot(args[1]);
            return;
        }

        bool created;
        using (Mutex m = new Mutex(true, "ClawdPet_SingleInstance", out created))
        {
            if (!created) return;
            Cfg.Load();
            Application app = new Application();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            if (Cfg.FirstRun) new SetupWindow().ShowDialog();
            PetWindow pet = new PetWindow();
            app.MainWindow = pet;
            app.ShutdownMode = ShutdownMode.OnMainWindowClose;
            app.Run(pet);
        }
    }
}

// Settings, stored as key=value lines in %AppData%\ClawdPet\settings.txt
static class Cfg
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string Orange = "#F26522";

    public static string Lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "de" ? "de" : "en";
    public static int Size = 5;
    public static bool Talk;
    public static string Color = Orange;
    public static bool FirstRun = true;
    public static bool ReadOnly;

    public static readonly int[] SizeVals = { 3, 5, 7, 10 };
    public static readonly string[] ColVals = { Orange, "#F06FA8", "#4A90D9", "#3FA66B", "#9B6FE8", "#3DD6D0" };

    public static string T(string de, string en) { return Lang == "de" ? de : en; }

    public static string[] SizeLabels()
    {
        return new string[] { T("Klein", "Small"), T("Mittel", "Medium"), T("Groß", "Large"), T("Riesig", "Huge") };
    }

    public static string[] ColLabels()
    {
        return new string[] { "Orange", "Pink", T("Blau", "Blue"), T("Grün", "Green"), T("Lila", "Purple"), T("Türkis", "Teal") };
    }

    static string FilePath
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ClawdPet", "settings.txt"); }
    }

    public static void Load()
    {
        try
        {
            foreach (string line in File.ReadAllLines(FilePath))
            {
                string[] kv = line.Split('=');
                if (kv.Length != 2) continue;
                if (kv[0] == "lang") { Lang = kv[1] == "de" ? "de" : "en"; FirstRun = false; }
                if (kv[0] == "size") Size = Math.Max(2, Math.Min(12, int.Parse(kv[1])));
                if (kv[0] == "talk") Talk = kv[1] == "1";
                if (kv[0] == "color" && kv[1].StartsWith("#")) Color = kv[1];
            }
        }
        catch { }
    }

    public static void Save()
    {
        if (ReadOnly) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
            File.WriteAllLines(FilePath, new string[] { "lang=" + Lang, "size=" + Size, "talk=" + (Talk ? "1" : "0"), "color=" + Color });
        }
        catch { }
    }

    public static bool AutoStart
    {
        get
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey))
                return k != null && k.GetValue("ClawdPet") != null;
        }
        set
        {
            if (ReadOnly) return;
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, true))
            {
                if (k == null) return;
                if (value) k.SetValue("ClawdPet", "\"" + System.Reflection.Assembly.GetExecutingAssembly().Location + "\"");
                else k.DeleteValue("ClawdPet", false);
            }
        }
    }
}

// First-run / settings dialog: language, size, colour and a few switches.
class SetupWindow : Window
{
    static readonly Brush Ink = PetWindow.B("#1A1915"), Paper = PetWindow.B("#FAF9F5"), Muted = PetWindow.B("#6E6D68");

    readonly Canvas logo = new Canvas();
    readonly TextBlock head = new TextBlock(), sub = new TextBlock(), hint = new TextBlock(), okText = new TextBlock();
    readonly TextBlock lLang = Label(), lSize = Label(), lColor = Label();
    readonly RadioButton de = new RadioButton(), en = new RadioButton();
    readonly ComboBox size = new ComboBox();
    readonly StackPanel swatches = new StackPanel();
    readonly CheckBox talk = new CheckBox(), auto = new CheckBox();
    readonly StackPanel root = new StackPanel();
    string color = Cfg.Color;

    static string T(string de, string en) { return Cfg.T(de, en); }

    static TextBlock Label()
    {
        TextBlock t = new TextBlock();
        t.FontWeight = FontWeights.SemiBold;
        t.Margin = new Thickness(0, 18, 0, 6);
        return t;
    }

    public SetupWindow()
    {
        Title = "Clawd";
        Width = 400;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;
        Background = Paper;
        Foreground = Ink;
        FontFamily = new FontFamily("Segoe UI");
        FontSize = 14;
        UseLayoutRounding = true;

        root.Margin = new Thickness(30, 26, 30, 26);

        logo.Width = 18 * 6;
        logo.Height = 10 * 6;
        logo.HorizontalAlignment = HorizontalAlignment.Center;
        root.Children.Add(logo);

        head.FontSize = 24;
        head.FontWeight = FontWeights.Bold;
        head.HorizontalAlignment = HorizontalAlignment.Center;
        head.Margin = new Thickness(0, 14, 0, 0);
        root.Children.Add(head);

        sub.Foreground = Muted;
        sub.TextWrapping = TextWrapping.Wrap;
        sub.TextAlignment = TextAlignment.Center;
        sub.Margin = new Thickness(0, 4, 0, 0);
        root.Children.Add(sub);

        root.Children.Add(lLang);
        StackPanel langRow = new StackPanel();
        langRow.Orientation = Orientation.Horizontal;
        de.Content = "Deutsch";
        en.Content = "English";
        en.Margin = new Thickness(24, 0, 0, 0);
        de.IsChecked = Cfg.Lang == "de";
        en.IsChecked = Cfg.Lang != "de";
        de.Checked += delegate { Cfg.Lang = "de"; Retext(); };
        en.Checked += delegate { Cfg.Lang = "en"; Retext(); };
        langRow.Children.Add(de);
        langRow.Children.Add(en);
        root.Children.Add(langRow);

        root.Children.Add(lSize);
        root.Children.Add(size);

        root.Children.Add(lColor);
        swatches.Orientation = Orientation.Horizontal;
        foreach (string v in Cfg.ColVals)
        {
            string val = v;
            Border b = new Border();
            b.Width = b.Height = 34;
            b.CornerRadius = new CornerRadius(8);
            b.Margin = new Thickness(0, 0, 8, 0);
            b.Background = PetWindow.B(val);
            b.BorderThickness = new Thickness(3);
            b.Cursor = Cursors.Hand;
            b.Tag = val;
            b.MouseLeftButtonDown += delegate { color = val; Mark(); };
            swatches.Children.Add(b);
        }
        root.Children.Add(swatches);

        talk.IsChecked = Cfg.Talk;
        talk.Margin = new Thickness(0, 20, 0, 0);
        root.Children.Add(talk);
        try { auto.IsChecked = Cfg.AutoStart; } catch { }
        auto.Margin = new Thickness(0, 8, 0, 0);
        root.Children.Add(auto);

        Border ok = new Border();
        ok.CornerRadius = new CornerRadius(10);
        ok.Background = PetWindow.B(Cfg.Orange);
        ok.Padding = new Thickness(0, 11, 0, 12);
        ok.Margin = new Thickness(0, 24, 0, 0);
        ok.Cursor = Cursors.Hand;
        okText.Foreground = Brushes.White;
        okText.FontWeight = FontWeights.Bold;
        okText.FontSize = 15;
        okText.HorizontalAlignment = HorizontalAlignment.Center;
        ok.Child = okText;
        ok.MouseEnter += delegate { ok.Opacity = 0.88; };
        ok.MouseLeave += delegate { ok.Opacity = 1; };
        ok.MouseLeftButtonUp += delegate { Close(); };
        root.Children.Add(ok);

        hint.FontSize = 12;
        hint.Foreground = Muted;
        hint.TextWrapping = TextWrapping.Wrap;
        hint.TextAlignment = TextAlignment.Center;
        hint.Margin = new Thickness(0, 10, 0, 0);
        root.Children.Add(hint);

        Content = root;
        Retext();
        Mark();

        KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Enter || e.Key == Key.Escape) Close(); };
        Closed += delegate
        {
            Cfg.Size = Cfg.SizeVals[Math.Max(0, size.SelectedIndex)];
            Cfg.Color = color;
            Cfg.Talk = talk.IsChecked == true;
            Cfg.Save();
            try { Cfg.AutoStart = auto.IsChecked == true; } catch { }
        };
    }

    void Retext()
    {
        head.Text = T("Hallo, ich bin Clawd!", "Hi, I'm Clawd!");
        sub.Text = T("Dein kleiner Mitbewohner für den Desktop. Wie hättest du mich gern?", "Your little desktop companion. How would you like me?");
        lLang.Text = T("Sprache", "Language");
        lSize.Text = T("Größe", "Size");
        lColor.Text = T("Farbe", "Color");
        int i = size.SelectedIndex;
        size.Items.Clear();
        foreach (string l in Cfg.SizeLabels()) size.Items.Add(l);
        size.SelectedIndex = i < 0 ? Math.Max(0, Array.IndexOf(Cfg.SizeVals, Cfg.Size)) : i;
        talk.Content = T("Sprechblasen anzeigen", "Show speech bubbles");
        auto.Content = T("Mit Windows starten", "Start with Windows");
        okText.Text = T("Los geht's!", "Let's go!");
        hint.Text = T("Alles lässt sich später per Rechtsklick auf Clawd ändern.", "You can change everything later by right-clicking Clawd.");
    }

    // Highlight the chosen swatch and redraw the little Clawd in that colour.
    void Mark()
    {
        foreach (object o in swatches.Children)
        {
            Border b = (Border)o;
            b.BorderBrush = (string)b.Tag == color ? Ink : Brushes.Transparent;
        }
        logo.Children.Clear();
        Brush c = PetWindow.B(color);
        Cell(c, 2, 0, 14, 8);
        Cell(c, 0, 3, 18, 2);
        foreach (int lx in new int[] { 3, 5, 12, 14 }) Cell(c, lx, 8, 1, 2);
        Cell(Ink, 5, 2, 1, 2);
        Cell(Ink, 12, 2, 1, 2);
    }

    void Cell(Brush b, int cx, int cy, int w, int h)
    {
        System.Windows.Shapes.Rectangle r = new System.Windows.Shapes.Rectangle();
        r.Fill = b;
        r.Width = w * 6;
        r.Height = h * 6;
        Canvas.SetLeft(r, cx * 6);
        Canvas.SetTop(r, cy * 6);
        logo.Children.Add(r);
    }

    public static void RenderShot(string path)
    {
        Cfg.ReadOnly = true;
        SetupWindow w = new SetupWindow();
        w.ContentRendered += delegate
        {
            int pw = (int)w.root.ActualWidth + 60, ph = (int)w.root.ActualHeight + 52;
            DrawingVisual dv = new DrawingVisual();
            using (DrawingContext dc = dv.RenderOpen())
            {
                dc.DrawRectangle(Paper, null, new Rect(0, 0, pw, ph));
                dc.DrawRectangle(new VisualBrush(w.root), null, new Rect(30, 26, w.root.ActualWidth, w.root.ActualHeight));
            }
            RenderTargetBitmap rtb = new RenderTargetBitmap(pw, ph, 96, 96, PixelFormats.Pbgra32);
            rtb.Render(dv);
            PngBitmapEncoder enc = new PngBitmapEncoder();
            enc.Frames.Add(BitmapFrame.Create(rtb));
            using (FileStream fs = File.Create(path)) enc.Save(fs);
            w.Close();
        };
        new Application().Run(w);
    }
}

class Particle
{
    public int Kind;
    public double X, Y, VX, VY, Life, Max, Size;
    public string Text;
    public Brush Brush;
}

class PetView : FrameworkElement
{
    public PetWindow Pet;
    protected override void OnRender(DrawingContext dc) { Pet.Draw(dc); }
}

class PetWindow : Window
{
    // Canvas size in cells (one cell = one "pixel" of Clawd)
    const int CW = 48, CH = 36;
    const int P_TEXT = 0, P_HEART = 1, P_STEAM = 2, P_CRUMB = 3;
    const int EYE_OPEN = 0, EYE_CLOSED = 1, EYE_HAPPY = 2, EYE_WIDE = 3, EYE_DIZZY = 4;
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X, Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize, dwTime; }
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO li);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);

    internal static Brush B(string hex)
    {
        SolidColorBrush b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        b.Freeze();
        return b;
    }

    static readonly Brush body = B(Cfg.Orange), ink = B("#1A1915"), white = B("#FFFFFF"),
        cream = B("#FAF9F5"), red = B("#E5484D"), yellow = B("#F5C542"), blue = B("#4A90D9"),
        grey = B("#C9C8C2"), greyDark = B("#8A8983"), brown = B("#8B5A2B"), brownDark = B("#5C3A1A"),
        cookie = B("#D9A55B"), gold = B("#E8C76A"), steam = B("#BBFFFFFF"), green = B("#3FA66B"),
        shine = B("#6E6D68"), purple = B("#9B6FE8"), pink = B("#F06FA8");
    static readonly Brush[] Palette = { red, yellow, blue, green, purple, pink, B("#FF9F43"), B("#3DD6D0") };

    static readonly string[] Heart = { ".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..." };
    static readonly string[] Balloon = { "..XXXX..", ".XXXXXX.", "XXoXXXXX", "XXoXXXXX", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", "..XXXX..", "...XX..." };
    static readonly string[] Cookie = { ".XX.", "XdXX", "XXdX", ".XX." };

    // Speech bubble lines: { German, English }
    static readonly string[][] PetLines = {
        new string[] { "Hihi!", "Das kitzelt!", "Mehr davon!", "Du bist nett!", "Schnurr...", "Nochmal!", "Hach, schön." },
        new string[] { "Hehe!", "That tickles!", "More, please!", "You're nice!", "Purr...", "Again!", "Ahh, lovely." } };
    static readonly string[][] IdleLines = {
        new string[] { "Was machst du da?", "Schöner Desktop!", "Ich bin Clawd!", "Zeit für eine Pause?", "Trink mal Wasser!", "Du schaffst das!", "Mir ist langweilig...", "Psst... Speichern nicht vergessen!", "Klick mich mal an!" },
        new string[] { "What are you up to?", "Nice desktop!", "I'm Clawd!", "Time for a break?", "Drink some water!", "You've got this!", "I'm bored...", "Psst... don't forget to save!", "Click me!" } };
    static readonly string[][] IdeaLines = {
        new string[] { "Idee!", "Heureka!", "Was wäre, wenn...", "42!", "Ich hab's!" },
        new string[] { "Idea!", "Eureka!", "What if...", "42!", "Got it!" } };
    static readonly string[][] CodeLines = {
        new string[] { "Nur noch ein Bug...", "Kompiliert!", "Läuft bei mir.", "git push --force?", "Wer hat das geschrieben? ...Ich." },
        new string[] { "Just one more bug...", "It compiles!", "Works on my machine.", "git push --force?", "Who wrote this? ...Me." } };
    static readonly string[][] DragLines = {
        new string[] { "Huch!", "Hey, lass mich runter!", "Wohin geht's?", "Ich kann fliegen!" },
        new string[] { "Whoa!", "Hey, put me down!", "Where are we going?", "I can fly!" } };
    static readonly string[] CodeBits = { "{ }", "</>", "01", "fn", "==", "//", "[ ]", ";" };

    static readonly string[] ActNames = { "walk", "run", "sleep", "code", "coffee", "read", "dance", "jump", "flip", "wave", "think", "cool", "climb", "juggle", "balloon", "stretch", "chase" };
    static readonly int[] ActWeights = { 30, 0, 6, 0, 6, 6, 5, 3, 0, 4, 0, 4, 0, 0, 0, 4, 0 };
    static readonly string[] ActLabelsEn = { "Walk", "Zoom", "Sleep", "Code", "Drink coffee", "Read", "Dance", "Hop", "Flip", "Wave", "Think", "Be cool", "Climb the wall", "Juggle", "Balloon ride", "Stretch", "Chase the mouse" };
    static readonly string[] ActLabelsDe = { "Spazieren", "Flitzen", "Schlafen", "Programmieren", "Kaffee trinken", "Lesen", "Tanzen", "Hüpfen", "Salto", "Winken", "Nachdenken", "Cool sein", "Wand hochklettern", "Jonglieren", "Ballonfahrt", "Strecken", "Maus jagen" };

    readonly Random rnd = new Random();
    readonly PetView view = new PetView();
    readonly List<Particle> parts = new List<Particle>();
    readonly Typeface monoFace = new Typeface(new FontFamily("Consolas"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
    readonly Typeface bubbleFace = new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
    DispatcherTimer timer;
    ContextMenu menu;
    WF.NotifyIcon tray;
    Pen bubblePen;
    DateTime last = DateTime.UtcNow;

    double dpi = 1, S = 5;

    // State
    string st = "idle", lastAct = "";
    double t, dur, anim, x, y, vx, vy, tx, rot, climbTop, spawnT, hopT, blinkT = 2, maxImpact;
    int phase, hops, side, dir = 1;
    bool air, moving;
    Rect work = SystemParameters.WorkArea;
    Point cur;
    double winLeft, ox, oy;

    // Reacting to the user
    readonly bool[] keyDown = new bool[256];
    double typingT = 99, tapT;
    int tapArm;
    bool typed, wasAway;
    Brush bodyB = body;

    // Mouse
    bool pressed, dragging;
    Point pressPos;
    double grabX, grabY, thvx, thvy;

    // Speech bubble
    string bubbleText;
    double bubbleT;

    public PetWindow()
    {
        Title = "Clawd";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.Manual;
        view.Pet = this;
        RenderOptions.SetEdgeMode(view, EdgeMode.Aliased);
        Content = view;

        ApplyScale();
        ApplyColor();
        x = work.Left + work.Width / 2;
        y = work.Bottom - 60 * S;
        Place();

        view.MouseLeftButtonDown += OnDown;
        view.MouseLeftButtonUp += OnUp;
        SourceInitialized += OnSourceInit;
        Loaded += OnLoaded;
        Closed += delegate { if (tray != null) { tray.Visible = false; tray.Dispose(); } };
    }

    // ---------- Startup ----------

    void OnSourceInit(object s, EventArgs e)
    {
        IntPtr h = new WindowInteropHelper(this).Handle;
        SetWindowLong(h, -20, GetWindowLong(h, -20) | 0x80); // WS_EX_TOOLWINDOW: keep out of Alt+Tab
        PresentationSource src = PresentationSource.FromVisual(this);
        if (src != null && src.CompositionTarget != null) dpi = src.CompositionTarget.TransformToDevice.M11;
        ApplyScale();
    }

    void OnLoaded(object s, RoutedEventArgs e)
    {
        BuildMenu();
        BuildTray();
        Set("fall");
        air = true;
        int hr = DateTime.Now.Hour;
        Say(hr < 5 ? T("Noch wach?", "Still up?") : hr < 11 ? T("Guten Morgen!", "Good morning!") : hr < 18 ? T("Hallo! Ich bin Clawd.", "Hi! I'm Clawd.") : T("Guten Abend!", "Good evening!"), 4);
        timer = new DispatcherTimer(DispatcherPriority.Render);
        timer.Interval = TimeSpan.FromMilliseconds(16);
        timer.Tick += Tick;
        last = DateTime.UtcNow;
        timer.Start();
    }

    void ApplyScale()
    {
        // Pick a cell size that lands on whole device pixels (crisp edges)
        S = Math.Max(1, Math.Round(Cfg.Size * dpi)) / dpi;
        Width = CW * S;
        Height = CH * S;
        bubblePen = new Pen(ink, Math.Max(1, 0.4 * S));
        bubblePen.Freeze();
    }

    void ApplyColor()
    {
        try { bodyB = B(Cfg.Color); } catch { bodyB = body; }
    }

    // ---------- Menus ----------

    static string T(string de, string en) { return Cfg.T(de, en); }

    MenuItem MI(string header, Action a)
    {
        MenuItem m = new MenuItem();
        m.Header = header;
        if (a != null) m.Click += delegate { a(); };
        return m;
    }

    // Submenu where exactly one entry is ticked.
    MenuItem Choice(string header, string[] labels, int selected, Action<int> pick)
    {
        MenuItem parent = MI(header, null);
        for (int i = 0; i < labels.Length; i++)
        {
            int idx = i;
            MenuItem m = MI(labels[i], null);
            m.IsCheckable = true;
            m.IsChecked = i == selected;
            m.Click += delegate
            {
                foreach (object o in parent.Items) ((MenuItem)o).IsChecked = o == m;
                pick(idx);
                Cfg.Save();
            };
            parent.Items.Add(m);
        }
        return parent;
    }

    void BuildMenu()
    {
        menu = new ContextMenu();
        menu.Items.Add(MI(T("Streicheln", "Pet"), PetIt));
        menu.Items.Add(MI(T("Füttern", "Feed"), delegate { Do("eat"); }));
        menu.Items.Add(MI(T("Komm her!", "Come here!"), delegate { Do("chase"); }));
        menu.Items.Add(new Separator());

        MenuItem acts = MI(T("Aktivität", "Activity"), null);
        string[] labels = Cfg.Lang == "de" ? ActLabelsDe : ActLabelsEn;
        for (int i = 0; i < ActNames.Length; i++)
        {
            string name = ActNames[i];
            acts.Items.Add(MI(labels[i], delegate { Do(name); }));
        }
        menu.Items.Add(acts);

        menu.Items.Add(Choice(T("Größe", "Size"), Cfg.SizeLabels(), Array.IndexOf(Cfg.SizeVals, Cfg.Size),
            delegate(int i) { Cfg.Size = Cfg.SizeVals[i]; ApplyScale(); }));
        menu.Items.Add(Choice(T("Farbe", "Color"), Cfg.ColLabels(), Array.IndexOf(Cfg.ColVals, Cfg.Color),
            delegate(int i) { Cfg.Color = Cfg.ColVals[i]; ApplyColor(); }));
        menu.Items.Add(Choice(T("Sprache", "Language"), new string[] { "Deutsch", "English" }, Cfg.Lang == "de" ? 0 : 1,
            delegate(int i) { Cfg.Lang = i == 0 ? "de" : "en"; bubbleT = 0; RebuildUi(); }));

        MenuItem mb = MI(T("Sprechblasen", "Speech bubbles"), null);
        mb.IsCheckable = true;
        mb.IsChecked = Cfg.Talk;
        mb.Click += delegate { Cfg.Talk = mb.IsChecked; if (!Cfg.Talk) bubbleT = 0; Cfg.Save(); };
        menu.Items.Add(mb);

        MenuItem ma = MI(T("Mit Windows starten", "Start with Windows"), null);
        ma.IsCheckable = true;
        try { ma.IsChecked = Cfg.AutoStart; } catch { }
        ma.Click += delegate { try { Cfg.AutoStart = ma.IsChecked; } catch { } };
        menu.Items.Add(ma);

        menu.Items.Add(MI(T("Einstellungen…", "Settings…"), OpenSetup));
        menu.Items.Add(new Separator());
        menu.Items.Add(MI(T("Beenden", "Quit"), Close));
        view.ContextMenu = menu;
    }

    void OpenSetup()
    {
        new SetupWindow().ShowDialog();
        ApplyScale();
        ApplyColor();
        if (!Cfg.Talk) bubbleT = 0;
        RebuildUi();
    }

    // Menus are built once per language, so rebuild them when it changes.
    void RebuildUi()
    {
        BuildMenu();
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        BuildTray();
    }

    void BuildTray()
    {
        tray = new WF.NotifyIcon();
        tray.Text = "Clawd";
        tray.Icon = MakeIcon();
        WF.ContextMenuStrip cm = new WF.ContextMenuStrip();
        cm.Items.Add(T("Zeigen / Verstecken", "Show / Hide"), null, delegate { ToggleVisible(); });
        cm.Items.Add(T("Zurück in die Mitte", "Back to the centre"), null, delegate
        {
            if (!IsVisible) Show();
            x = work.Left + work.Width / 2;
            y = work.Bottom - 60 * S;
            Set("fall");
            air = true;
        });
        cm.Items.Add(T("Beenden", "Quit"), null, delegate { Close(); });
        tray.ContextMenuStrip = cm;
        tray.DoubleClick += delegate { ToggleVisible(); };
        tray.Visible = true;
    }

    void ToggleVisible()
    {
        if (IsVisible) Hide(); else Show();
    }

    static SD.Icon MakeIcon()
    {
        SD.Bitmap bmp = new SD.Bitmap(32, 32);
        using (SD.Graphics g = SD.Graphics.FromImage(bmp))
        using (SD.SolidBrush o = new SD.SolidBrush(SD.Color.FromArgb(0xF2, 0x65, 0x22)))
        using (SD.SolidBrush k = new SD.SolidBrush(SD.Color.FromArgb(0x1A, 0x19, 0x15)))
        {
            g.Clear(SD.Color.Transparent);
            g.FillRectangle(o, 2, 6, 28, 16);
            g.FillRectangle(o, 0, 12, 32, 4);
            foreach (int lx in new int[] { 4, 8, 22, 26 }) g.FillRectangle(o, lx, 22, 2, 4);
            g.FillRectangle(k, 8, 10, 2, 4);
            g.FillRectangle(k, 22, 10, 2, 4);
        }
        return SD.Icon.FromHandle(bmp.GetHicon());
    }

    // ---------- Mouse ----------

    void ReadCursor()
    {
        POINT p;
        if (GetCursorPos(out p)) cur = new Point(p.X / dpi, p.Y / dpi);
    }

    void OnDown(object s, MouseButtonEventArgs e)
    {
        ReadCursor();
        if (e.ClickCount == 2)
        {
            if (!air && y >= work.Bottom - 1) Set("flip");
            return;
        }
        pressed = true;
        pressPos = cur;
        grabX = x - cur.X;
        grabY = y - cur.Y;
        thvx = thvy = 0;
        view.CaptureMouse();
    }

    void OnUp(object s, MouseButtonEventArgs e)
    {
        if (!pressed) return;
        pressed = false;
        view.ReleaseMouseCapture();
        if (dragging)
        {
            dragging = false;
            Set("fall");
            air = true;
            double lim = 500 * S;
            vx = Math.Max(-lim, Math.Min(lim, thvx));
            vy = Math.Max(-lim, Math.Min(lim, thvy));
            if (Math.Abs(vx) + Math.Abs(vy) > 150 * S) Say(T("Huiii!", "Wheee!"), 1.5);
        }
        else if (st == "sleep")
        {
            Set("idle");
            Say(T("Hm? Bin wach!", "Huh? I'm awake!"), 2.5);
        }
        else PetIt();
    }

    void PetIt()
    {
        Set("pet");
        for (int i = 0; i < 4; i++)
            Spawn(P_HEART, -6 + R() * 12, -11 - R() * 3, (R() - 0.5) * 3, -5 - R() * 3, 1.3 + R() * 0.5, null, 0, Pal());
        Say(Pick(PetLines), 2);
    }

    void Do(string name)
    {
        if (dragging) return;
        Set(name);
    }

    // ---------- Logic ----------

    double R() { return rnd.NextDouble(); }
    string Pick(string[] a) { return a[rnd.Next(a.Length)]; }
    string Pick(string[][] a) { return Pick(a[Cfg.Lang == "de" ? 0 : 1]); }
    double Sn(double v) { return Math.Round(v * dpi) / dpi; }
    double RandX() { return work.Left + 12 * S + R() * (work.Width - 24 * S); }

    void Say(string text, double secs)
    {
        if (!Cfg.Talk) return;
        bubbleText = text;
        bubbleT = secs;
    }

    void Spawn(int kind, double px, double py, double pvx, double pvy, double life, string text, double size, Brush b)
    {
        Particle p = new Particle();
        p.Kind = kind; p.X = px; p.Y = py; p.VX = pvx; p.VY = pvy;
        p.Life = p.Max = life; p.Text = text; p.Size = size; p.Brush = b;
        parts.Add(p);
    }

    bool Every(double interval, double dt)
    {
        spawnT -= dt;
        if (spawnT > 0) return false;
        spawnT = interval;
        return true;
    }

    void Launch(double cells)
    {
        vy = -Math.Sqrt(2 * 260 * S * cells * S);
        air = true;
    }

    bool MoveTo(double target, double speed, double dt)
    {
        double d = target - x;
        if (Math.Abs(d) <= speed * dt) { x = target; return true; }
        dir = d > 0 ? 1 : -1;
        x += dir * speed * dt;
        moving = true;
        return false;
    }

    void Set(string s)
    {
        st = s; t = 0; phase = 0; rot = 0; spawnT = 0; hopT = 0;
        side = x < work.Left + work.Width / 2 ? -1 : 1;
        switch (s)
        {
            case "idle":
                dur = 4 + R() * 8;
                if (R() < 0.12 && bubbleT <= 0) Say(Pick(IdleLines), 3.5);
                break;
            case "walk": case "run": tx = RandX(); break;
            case "sleep": dur = 14 + R() * 14; break;
            case "code": dur = 10 + R() * 10; typed = false; if (R() < 0.6) Say(Pick(CodeLines), 3); break;
            case "coffee": dur = 8 + R() * 5; break;
            case "read": dur = 10 + R() * 6; break;
            case "dance": dur = 6 + R() * 4; break;
            case "jump": hops = 3; Launch(12); break;
            case "flip": Launch(18); Say(T("Hepp!", "Hup!"), 1.2); break;
            case "wave": dur = 3; Say(T("Hallo!", "Hello!"), 2.5); break;
            case "think": dur = 6; Say(". . .", 3.2); break;
            case "cool": dur = 8; Say(T("Läuft.", "Smooth."), 2.5); break;
            case "juggle": dur = 8; break;
            case "balloon": dur = 4 + R() * 3; break;
            case "stretch": dur = 2.5; Say(T("*gähn*", "*yawn*"), 2); break;
            case "chase": dur = 9; break;
            case "eat": dur = 3.6; break;
            case "pet": dur = 1.5; break;
            case "drag": Say(Pick(DragLines), 2); break;
            case "fall": maxImpact = 0; break;
            case "dizzy": dur = 2.5; break;
        }
    }

    void PickActivity()
    {
        int hr = DateTime.Now.Hour;
        bool night = hr >= 23 || hr < 6;
        int total = 0;
        for (int i = 0; i < ActNames.Length; i++)
            if (ActNames[i] != lastAct) total += Weight(i, night);
        int r = rnd.Next(total);
        for (int i = 0; i < ActNames.Length; i++)
        {
            if (ActNames[i] == lastAct) continue;
            r -= Weight(i, night);
            if (r < 0) { lastAct = ActNames[i]; Set(ActNames[i]); return; }
        }
    }

    static int Weight(int i, bool night)
    {
        return ActNames[i] == "sleep" && night ? ActWeights[i] * 5 : ActWeights[i];
    }

    void Tick(object s, EventArgs e)
    {
        DateTime now = DateTime.UtcNow;
        double dt = Math.Min(0.1, (now - last).TotalSeconds);
        last = now;
        work = SystemParameters.WorkArea;
        ReadCursor();
        anim += dt;
        if (bubbleT > 0) bubbleT -= dt;
        blinkT -= dt;
        if (blinkT < -0.13) blinkT = 1.5 + R() * 4;
        ReadInput(dt);
        if (menu == null || !menu.IsOpen) UpdatePet(dt);
        UpdateParticles(dt);
        Place();
        view.InvalidateVisual();
    }

    Brush Pal() { return Palette[rnd.Next(Palette.Length)]; }

    // Only counts THAT keys are being pressed - never which ones. Nothing is stored or sent.
    void ReadInput(double dt)
    {
        int hits = 0;
        for (int vk = 8; vk < 255; vk++)
        {
            bool down = (GetAsyncKeyState(vk) & 0x8000) != 0;
            if (down && !keyDown[vk]) hits++;
            keyDown[vk] = down;
        }
        typingT += dt;
        tapT -= dt;
        LASTINPUTINFO li = new LASTINPUTINFO();
        li.cbSize = 8;
        double idle = GetLastInputInfo(ref li) ? unchecked((uint)Environment.TickCount - li.dwTime) / 1000.0 : 0;
        bool calm = !air && !dragging && !pressed && y >= work.Bottom - 0.5
            && Array.IndexOf(new string[] { "drag", "fall", "dizzy", "pet", "eat", "jump", "flip", "climb", "balloon", "chase" }, st) < 0;

        if (hits > 0)
        {
            typingT = 0;
            tapT = 0.12;
            tapArm = 1 - tapArm;
            if (st != "code" && calm) Set("code");
            if (st == "code")
            {
                typed = true;
                Spawn(P_TEXT, -5 + R() * 10, -7, (R() - 0.5) * 3, -5, 1.2, Pick(CodeBits), 2.2, Pal());
            }
        }
        // Nobody there -> fall asleep; back again -> wake up and wave
        bool away = idle > 120;
        if (away && calm && st != "sleep") Set("sleep");
        if (wasAway && !away && st == "sleep") Set("wave");
        wasAway = away;
    }

    void Place()
    {
        winLeft = Sn(x - CW * S / 2);
        Left = winLeft;
        Top = Sn(y - (CH - 1) * S);
    }

    void UpdateParticles(double dt)
    {
        for (int i = parts.Count - 1; i >= 0; i--)
        {
            Particle p = parts[i];
            p.Life -= dt;
            if (p.Life <= 0) { parts.RemoveAt(i); continue; }
            if (p.Kind == P_CRUMB) p.VY += 30 * dt;
            p.X += p.VX * dt;
            p.Y += p.VY * dt;
        }
    }

    void Physics(double dt)
    {
        vy += 260 * S * dt;
        x += vx * dt;
        y += vy * dt;
        double minX = work.Left + 9 * S, maxX = work.Right - 9 * S;
        if (x < minX) { x = minX; vx = -vx * 0.6; }
        if (x > maxX) { x = maxX; vx = -vx * 0.6; }
        if (y < work.Top + 12 * S) { y = work.Top + 12 * S; vy = Math.Abs(vy) * 0.5; }
        if (y < work.Bottom) return;
        y = work.Bottom;
        if (st == "fall" && vy > 60 * S)
        {
            if (vy > maxImpact) maxImpact = vy;
            vy = -vy * 0.4;
            vx *= 0.7;
            return;
        }
        vx = vy = 0;
        air = false;
        if (st == "jump")
        {
            hops--;
            if (hops > 0) Launch(12); else Set("idle");
        }
        else if (st == "flip") Set("idle");
        else if (st == "fall")
        {
            if (maxImpact > 300 * S) { Set("dizzy"); Say(T("Mir ist schwindelig...", "I'm dizzy..."), 2.5); }
            else Set("idle");
        }
    }

    void UpdatePet(double dt)
    {
        t += dt;
        moving = false;
        double ground = work.Bottom;

        if (pressed && !dragging)
        {
            double dx = cur.X - pressPos.X, dy = cur.Y - pressPos.Y;
            if (dx * dx + dy * dy > 25)
            {
                dragging = true;
                air = false;
                Set("drag");
            }
        }
        if (dragging)
        {
            double nx = cur.X + grabX, ny = cur.Y + grabY;
            if (dt > 0)
            {
                thvx = thvx * 0.6 + (nx - x) / dt * 0.4;
                thvy = thvy * 0.6 + (ny - y) / dt * 0.4;
            }
            x = Math.Max(work.Left + 9 * S, Math.Min(work.Right - 9 * S, nx));
            y = Math.Max(work.Top + 12 * S, Math.Min(work.Bottom, ny));
            return;
        }

        bool floating = st == "climb" || st == "balloon";
        if (!air && !floating && y < ground - 0.5) air = true;
        if (air) Physics(dt);

        switch (st)
        {
            case "idle":
                if (t > dur && !air) PickActivity();
                break;
            case "walk":
                if (MoveTo(tx, 12 * S, dt)) Set("idle");
                break;
            case "run":
                if (MoveTo(tx, 45 * S, dt)) Set("idle");
                break;
            case "sleep":
                if (Every(1.3, dt)) Spawn(P_TEXT, 6, -9, 2.2, -3.5, 2.4, "z", 2.2, Pal());
                if (t > dur && !wasAway) { Set("idle"); Say(T("Gut geschlafen!", "Slept well!"), 2.5); }
                break;
            case "code":
                if (typed) { if (typingT > 2.5) Set("idle"); break; }
                if (Every(0.7, dt)) Spawn(P_TEXT, -5 + R() * 10, -7, (R() - 0.5) * 2, -4, 1.8, Pick(CodeBits), 2.2, Pal());
                if (t > dur) Set("idle");
                break;
            case "coffee":
                if (t % 4 < 3 && Every(0.5, dt)) Spawn(P_STEAM, 10.5 + R() * 1.5, -10, (R() - 0.5), -2.5, 1.2, null, 0, steam);
                if (t > dur) { Set("idle"); Say(T("Ahh, Kaffee.", "Ahh, coffee."), 2); }
                break;
            case "dance":
                if (Every(0.55, dt)) Spawn(P_TEXT, -9 + R() * 18, -11, (R() - 0.5) * 3, -4, 1.6, R() < 0.5 ? "♪" : "♫", 3, Pal());
                if (R() < 0.15) Spawn(P_CRUMB, -14 + R() * 28, -22, (R() - 0.5) * 4, 2, 1.4, null, 0, Pal());
                if (t > dur) Set("idle");
                break;
            case "flip":
                {
                    double T = 2 * Math.Sqrt(2 * 260 * S * 18 * S) / (260 * S);
                    rot = 360 * Math.Min(1, t / T) * dir;
                }
                break;
            case "think":
                if (phase == 0 && t > 3.5)
                {
                    phase = 1;
                    Say(Pick(IdeaLines), 2.3);
                }
                if (t > dur) Set("idle");
                break;
            case "climb":
                if (phase == 0)
                {
                    if (MoveTo(side < 0 ? work.Left + 6 * S : work.Right - 6 * S, 14 * S, dt))
                    {
                        phase = 1;
                        climbTop = ground - work.Height * (0.3 + R() * 0.4);
                    }
                }
                else if (phase == 1)
                {
                    rot = side < 0 ? 90 : -90;
                    moving = true;
                    y -= 9 * S * dt;
                    if (y <= climbTop) { phase = 2; t = 0; }
                }
                else
                {
                    rot = side < 0 ? 90 : -90;
                    if (t > 2.5)
                    {
                        int sd = side;
                        Set("fall");
                        air = true;
                        vx = -sd * 25 * S;
                        vy = -20 * S;
                        Say(T("Huiii!", "Wheee!"), 1.5);
                    }
                }
                break;
            case "chase":
                {
                    double target = Math.Max(work.Left + 9 * S, Math.Min(work.Right - 9 * S, cur.X));
                    hopT -= dt;
                    if (Math.Abs(target - x) > 12 * S) MoveTo(target, 40 * S, dt);
                    else if (!air && hopT <= 0) { Launch(4); hopT = 0.9; }
                    if (t > dur && !air) { Set("idle"); Say(T("Hab dich!", "Gotcha!"), 2); }
                }
                break;
            case "balloon":
                y -= 12 * S * dt;
                x += Math.Sin(t * 1.3) * 8 * S * dt;
                if (t > dur || y < work.Top + 45 * S)
                {
                    for (int i = 0; i < 9; i++)
                        Spawn(P_CRUMB, 8, -20, (R() - 0.5) * 30, -R() * 14, 0.8, null, 0, red);
                    Set("fall");
                    air = true;
                    Say(T("Peng!", "Pop!"), 1.5);
                }
                break;
            case "stretch":
                if (t > dur) Set(R() < 0.5 ? "sleep" : "idle");
                break;
            case "eat":
                if (Every(0.9, dt) && t > 0.5)
                    for (int i = 0; i < 4; i++)
                        Spawn(P_CRUMB, 10, -9, (R() - 0.5) * 8, -R() * 5, 0.7, null, 0, cookie);
                if (t > dur) { Set("idle"); Say(T("Lecker!", "Yummy!"), 2); }
                break;
            case "read": case "wave": case "cool": case "juggle": case "pet": case "dizzy":
                if (t > dur) Set("idle");
                break;
        }

        x = Math.Max(work.Left + 6 * S, Math.Min(work.Right - 6 * S, x));
        if (!air && st != "climb" && st != "balloon" && y > ground) y = ground;
    }

    // ---------- Drawing ----------

    void C(DrawingContext dc, Brush b, double cx, double cy, double w, double h)
    {
        double x0 = Sn(ox + cx * S), y0 = Sn(oy + cy * S), x1 = Sn(ox + (cx + w) * S), y1 = Sn(oy + (cy + h) * S);
        if (x1 <= x0 || y1 <= y0) return;
        dc.DrawRectangle(b, null, new Rect(x0, y0, x1 - x0, y1 - y0));
    }

    void Bmp(DrawingContext dc, string[] rows, double cx, double cy, double u, Brush main, Brush alt, int maxCols)
    {
        for (int r = 0; r < rows.Length; r++)
            for (int c = 0; c < rows[r].Length && c < maxCols; c++)
            {
                char ch = rows[r][c];
                if (ch == '.') continue;
                C(dc, ch == 'X' ? main : alt, cx + c * u, cy + r * u, u, u);
            }
    }

    void Txt(DrawingContext dc, string s, double cx, double cy, double sizeCells, Brush b)
    {
        FormattedText ft = new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, monoFace, Math.Max(7, sizeCells * S), b, dpi);
        dc.DrawText(ft, new Point(ox + cx * S - ft.Width / 2, oy + cy * S - ft.Height / 2));
    }

    void Eye(DrawingContext dc, int mode, double ex, double ey)
    {
        // ex = left edge of the 1-cell-wide eye
        switch (mode)
        {
            case EYE_OPEN: C(dc, ink, ex, ey, 1, 2); break;
            case EYE_CLOSED: C(dc, ink, ex - 0.5, ey + 1, 2, 0.7); break;
            case EYE_HAPPY:
                C(dc, ink, ex - 1, ey + 1, 1, 1);
                C(dc, ink, ex, ey, 1, 1);
                C(dc, ink, ex + 1, ey + 1, 1, 1);
                break;
            case EYE_WIDE:
                C(dc, ink, ex - 0.5, ey - 0.5, 2, 2.5);
                C(dc, white, ex - 0.5, ey - 0.5, 1, 1);
                break;
            case EYE_DIZZY:
                C(dc, ink, ex - 1, ey - 0.5, 1, 1);
                C(dc, ink, ex + 1, ey - 0.5, 1, 1);
                C(dc, ink, ex, ey + 0.5, 1, 1);
                C(dc, ink, ex - 1, ey + 1.5, 1, 1);
                C(dc, ink, ex + 1, ey + 1.5, 1, 1);
                break;
        }
    }

    public void Draw(DrawingContext dc)
    {
        double sway = 0, lift = 0, bob, aL = 0, aR = 0, tall = 0;
        int eye = EYE_OPEN, lx = 0, ly = 0;
        bool sit = false, dangle = false, glasses = false;
        bool fast = st == "run" || st == "chase";
        int frame = (int)(anim * (fast ? 12 : 6)) % 2;
        int beat = (int)(anim * 6) % 2;

        if (Math.Abs(cur.X - x) > 8 * S) lx = cur.X > x ? 1 : -1;
        if (cur.Y < y - 30 * S) ly = -1;
        bob = moving ? (frame == 0 ? 0 : -0.6) : Math.Sin(anim * 2.2) * 0.25;
        if (air) { bob = 0; if (vy < 0) aL = aR = -2; }

        switch (st)
        {
            case "sleep":
                sit = true; eye = EYE_CLOSED; lx = ly = 0;
                bob = (Math.Sin(anim * 1.3) + 1) * 0.3;
                break;
            case "code":
                lx = 0; ly = 1;
                if (!typed) { aL = (int)(anim * 9) % 2; aR = 1 - aL; }
                else if (tapT > 0) { if (tapArm == 0) aL = 1; else aR = 1; }
                break;
            case "coffee":
                if (t % 4 >= 3) { aR = -2; eye = EYE_CLOSED; }
                break;
            case "read":
                ly = 1; lx = (int)(anim * 1.5) % 3 - 1;
                aL = aR = 2;
                break;
            case "dance":
                lift = -Math.Abs(Math.Sin(anim * 6)) * 1.5;
                sway = Math.Sin(anim * 3) * 1.5;
                if (Math.Sin(anim * 3) > 0) aL = -3; else aR = -3;
                eye = EYE_HAPPY; lx = ly = 0;
                break;
            case "jump": case "flip":
                eye = EYE_HAPPY; lx = ly = 0;
                break;
            case "wave":
                aR = -3 + beat; eye = EYE_HAPPY; lx = ly = 0;
                break;
            case "think":
                if (phase == 0) { lx = 1; ly = -1; aR = -1; }
                else { eye = EYE_HAPPY; lx = ly = 0; aL = aR = -2; }
                break;
            case "cool":
                glasses = true; lx = ly = 0;
                break;
            case "climb":
                if (phase > 0) { lx = 0; ly = phase == 2 ? 1 : -1; }
                break;
            case "juggle":
                lx = 0; ly = -1; aL = -beat; aR = -(1 - beat);
                break;
            case "balloon":
                aR = -3; ly = -1; lx = 0; dangle = true; bob = 0;
                break;
            case "stretch":
                aL = aR = -3; eye = EYE_CLOSED; tall = 1; bob = 0;
                break;
            case "eat":
                aR = -2;
                if (t % 0.9 < 0.3) eye = EYE_HAPPY;
                lx = ly = 0;
                break;
            case "pet":
                eye = EYE_HAPPY; lx = ly = 0;
                lift = -Math.Abs(Math.Sin(t * 10)) * 1.0;
                break;
            case "drag":
                eye = EYE_WIDE; lx = ly = 0; dangle = true; aL = aR = -2; bob = 0;
                break;
            case "fall":
                eye = EYE_WIDE; lx = ly = 0; aL = aR = -2;
                break;
            case "dizzy":
                eye = EYE_DIZZY; lx = ly = 0;
                sway = Math.Sin(anim * 5) * 0.8;
                break;
            case "chase":
                if (!moving) eye = EYE_HAPPY;
                break;
        }
        if (blinkT < 0 && eye == EYE_OPEN) eye = EYE_CLOSED;

        double baseX = CW * S / 2, baseY = (CH - 1) * S;
        ox = baseX + sway * S;
        oy = baseY + lift * S;
        double so = sit ? 2 : 0;
        double bodyTop = -10 - tall + bob + so;
        double bodyBot = sit ? 0 : -2 + bob;
        double armY = -7 + bob + so;

        if (rot != 0) dc.PushTransform(new RotateTransform(rot, ox, oy - 6 * S));

        if (st == "balloon")
        {
            C(dc, cream, 7.85, -16, 0.3, 6 + bob);
            Bmp(dc, Balloon, 4, -25, 1, red, white, 99);
        }

        if (!sit)
        {
            double[] legX = { -6, -4, 3, 5 };
            for (int i = 0; i < 4; i++)
            {
                double len = -bodyBot;
                if (dangle) len = (i + (int)(anim * 10)) % 2 == 0 ? 2 : 1.2;
                else if (air) len = 2;
                else if (moving && i % 2 == frame) len = 1;
                C(dc, bodyB, legX[i], bodyBot, 1, len);
            }
        }
        C(dc, bodyB, -7, bodyTop, 14, bodyBot - bodyTop);
        C(dc, bodyB, -9, armY + aL, 2, 2);
        C(dc, bodyB, 7, armY + aR, 2, 2);

        double eyeY = -8 - tall * 0.5 + bob + so + ly;
        Eye(dc, eye, -4 + lx, eyeY);
        Eye(dc, eye, 3 + lx, eyeY);

        if (glasses)
        {
            double gy = -8.5 + bob;
            C(dc, ink, -7, gy, 14, 1);
            C(dc, ink, -6, gy, 5, 3);
            C(dc, ink, 1, gy, 5, 3);
            C(dc, shine, -5, gy + 1, 1, 1);
            C(dc, shine, 2, gy + 1, 1, 1);
        }

        switch (st)
        {
            case "code":
                C(dc, grey, -5, -5, 10, 4);
                C(dc, Palette[(int)(anim * 3) % Palette.Length], -1, -4, 2, 2);
                C(dc, greyDark, -6, -1, 12, 1);
                break;
            case "read":
                C(dc, brown, -6, -5, 12, 4);
                C(dc, brownDark, -0.5, -5, 1, 4);
                C(dc, gold, -4.5, -4, 3, 1);
                C(dc, gold, 1.5, -4, 3, 1);
                break;
            case "coffee":
                {
                    double cy = armY + aR - 2.5;
                    C(dc, white, 9.5, cy, 3, 3);
                    C(dc, white, 12.5, cy + 1, 1, 1);
                    C(dc, brownDark, 9.5, cy, 3, 0.6);
                }
                break;
            case "eat":
                Bmp(dc, Cookie, 9, armY + aR - 3.5, 1, cookie, brownDark, 4 - Math.Min(3, (int)(t / 0.9)));
                break;
            case "juggle":
                {
                    Brush[] cols = { red, yellow, blue };
                    for (int i = 0; i < 3; i++)
                    {
                        double p = anim * 1.2 + i / 3.0;
                        double f = p - Math.Floor(p);
                        bool ltr = (int)Math.Floor(p) % 2 == 0;
                        double bx = ltr ? -8 + 16 * f : 8 - 16 * f;
                        double by = -10 - 12 * 4 * f * (1 - f);
                        C(dc, cols[i], bx - 1, by - 1, 2, 2);
                    }
                }
                break;
        }

        if (rot != 0) dc.Pop();

        // Overlays (neither rotated nor swayed with the body)
        ox = baseX; oy = baseY;

        if (st == "dizzy")
            for (int i = 0; i < 3; i++)
            {
                double a = anim * 4 + i * 2.094;
                double sx = 7 * Math.Cos(a), sy = -12.5 + 1.5 * Math.Sin(a);
                C(dc, yellow, sx - 0.5, sy - 1.5, 1, 3);
                C(dc, yellow, sx - 1.5, sy - 0.5, 3, 1);
            }

        foreach (Particle p in parts)
        {
            dc.PushOpacity(Math.Min(1, p.Life / (p.Max * 0.4)));
            switch (p.Kind)
            {
                case P_TEXT: Txt(dc, p.Text, p.X, p.Y, p.Size * (1 + (1 - p.Life / p.Max) * 0.5), p.Brush); break;
                case P_HEART: Bmp(dc, Heart, p.X - 1.75, p.Y - 1.5, 0.5, p.Brush, p.Brush, 99); break;
                default: C(dc, p.Brush, p.X, p.Y, 0.7, 0.7); break;
            }
            dc.Pop();
        }

        if (bubbleT > 0 && bubbleText != null) DrawBubble(dc, sit);
    }

    void DrawBubble(DrawingContext dc, bool sit)
    {
        FormattedText ft = new FormattedText(bubbleText, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, bubbleFace, Math.Max(9, 2.4 * S), ink, dpi);
        double maxW = 34 * S;
        ft.MaxTextWidth = maxW;
        ft.TextAlignment = TextAlignment.Center;
        double padX = 1.6 * S, padY = 0.9 * S;
        double bw = ft.Width + 2 * padX, bh = ft.Height + 2 * padY;
        double winW = CW * S, mid = winW / 2;

        // clamp to the screen first, then to the window
        double bx = Math.Max(work.Left + bw / 2 + 2, Math.Min(work.Right - bw / 2 - 2, winLeft + mid)) - winLeft;
        bx = Math.Max(bw / 2 + 1, Math.Min(winW - bw / 2 - 1, bx));
        double by = (CH - 1) * S - (sit ? 11 : 13) * S - 1.5 * S;
        Rect r = new Rect(bx - bw / 2, by - bh, bw, bh);
        double tailX = Math.Max(r.Left + 2 * S, Math.Min(r.Right - 2 * S, mid));

        dc.PushOpacity(Math.Min(1, bubbleT / 0.3));
        dc.DrawRoundedRectangle(cream, bubblePen, r, S, S);
        StreamGeometry g = new StreamGeometry();
        using (StreamGeometryContext c = g.Open())
        {
            c.BeginFigure(new Point(tailX - S, by - bubblePen.Thickness), true, false);
            c.LineTo(new Point(tailX, by + 1.4 * S), true, false);
            c.LineTo(new Point(tailX + S, by - bubblePen.Thickness), true, false);
        }
        g.Freeze();
        dc.DrawGeometry(cream, bubblePen, g);
        dc.DrawText(ft, new Point(bx - maxW / 2, r.Top + padY));
        dc.Pop();
    }

    // ---------- Developer helper: render a sheet of poses into a PNG ----------

    public static void RenderSheet(string path)
    {
        PetWindow w = new PetWindow();
        string[] states = { "idle", "walk", "sleep", "code", "coffee", "read", "dance", "wave", "cool", "juggle", "balloon", "stretch", "eat", "pet", "drag", "dizzy" };
        int cols = 4, rows = (states.Length + cols - 1) / cols;
        double tw = CW * w.S, th = CH * w.S;
        DrawingVisual dv = new DrawingVisual();
        RenderOptions.SetEdgeMode(dv, EdgeMode.Aliased);
        using (DrawingContext dc = dv.RenderOpen())
        {
            dc.DrawRectangle(B("#243447"), null, new Rect(0, 0, cols * tw, rows * th));
            for (int i = 0; i < states.Length; i++)
            {
                w.parts.Clear();
                w.st = states[i];
                w.t = 3.1; w.anim = 1.3; w.phase = 0; w.rot = 0; w.blinkT = 1;
                w.moving = states[i] == "walk";
                w.bubbleT = 0;
                w.x = 500; w.y = 500; w.cur = new Point(500, 500); w.winLeft = 500 - tw / 2;
                w.work = new Rect(0, 0, 1000, 1000);
                if (states[i] == "climb") { w.phase = 1; w.rot = 90; w.moving = true; }
                if (states[i] == "sleep") w.Spawn(P_TEXT, 8, -12, 0, 0, 2, "z", 2.6, cream);
                if (states[i] == "pet") { w.Spawn(P_HEART, -4, -13, 0, 0, 2, null, 0, red); w.Spawn(P_HEART, 4, -15, 0, 0, 2, null, 0, red); }
                if (states[i] == "code") { w.typed = true; w.tapT = 0.1; w.Spawn(P_TEXT, -3, -13, 0, 0, 2, "{ }", 2.2, green); w.Spawn(P_TEXT, 5, -16, 0, 0, 2, "</>", 2.2, yellow); }
                if (states[i] == "dance") { w.Spawn(P_TEXT, -9, -15, 0, 0, 2, "\u266A", 3, pink); w.Spawn(P_TEXT, 8, -17, 0, 0, 2, "\u266B", 3, blue); }
                if (states[i] == "idle") { w.bubbleText = "Hi! I'm Clawd."; w.bubbleT = 3; }
                dc.PushTransform(new TranslateTransform((i % cols) * tw, (i / cols) * th));
                w.Draw(dc);
                dc.Pop();
            }
        }
        RenderTargetBitmap rtb = new RenderTargetBitmap((int)(cols * tw), (int)(rows * th), 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);
        PngBitmapEncoder enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(rtb));
        using (FileStream fs = File.Create(path)) enc.Save(fs);
    }
}
