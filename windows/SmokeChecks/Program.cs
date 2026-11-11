using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using ScreenshotApp.Windows;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
        var app = new App();
        app.InitializeComponent();
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        int exitCode = 1;
        var dispatcher = Dispatcher.CurrentDispatcher;
        dispatcher.InvokeAsync(async () =>
        {
            var root = Path.Combine(Path.GetTempPath(), $"ScreenshotApp-smoke-{Guid.NewGuid():N}");
            try
            {
                Console.WriteLine($"OS {Environment.OSVersion.Version}; process {RuntimeInformation.ProcessArchitecture}");
                await CheckAsync(app, new LocalStore(root));
                exitCode = 0;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(error);
            }
            finally
            {
                foreach (Window window in app.Windows.Cast<Window>().ToArray().Reverse())
                    window.Close();
                if (Directory.Exists(root))
                    Directory.Delete(root, true);
                dispatcher.InvokeShutdown();
            }
        });
        Dispatcher.Run();
        return exitCode;
    }

    private static async Task CheckAsync(App app, LocalStore store)
    {
        var source = Raster.Render(150, 100, drawing =>
        {
            drawing.DrawRectangle(Brushes.White, null, new Rect(0, 0, 150, 100));
            drawing.DrawRectangle(Brushes.Black, null, new Rect(105, 0, 10, 100));
        });
        var document = new ScreenshotDocument(source);
        document.AddArrow(new Point(10, 50), new Point(85, 50));
        document.AddText(new Point(6, 6), "Тест PNG");
        document.AddBlur(new Rect(95, 20, 30, 30));
        var edited = document.Render();
        Require(Pixel(edited, 35, 50).R > Pixel(edited, 35, 50).B, "Arrow color");
        Require(Pixel(edited, 7, 14) == Colors.Black, "Text background");
        byte blurred = Pixel(edited, 108, 32).R;
        Require(blurred is > 10 and < 245, $"Blur mixed adjacent pixels ({blurred})");
        Require(Pixel(edited, 108, 60) == Colors.Black, "Blur stayed inside selection");
        document.Undo();
        Require(Pixel(document.Render(), 108, 32) == Colors.Black, "Undo restored pixels");
        document.Undo();
        document.Undo();
        Require(!document.CanUndo && document.Render() == source, "Undo restored original");

        string path = store.NewCapturePath();
        LocalStore.SavePng(path, source);
        LocalStore.SavePng(path, edited);
        var restored = LocalStore.OpenPng(path);
        Require(restored.PixelWidth == 150 && restored.PixelHeight == 100 &&
                Pixel(restored, 108, 32).R == blurred, "PNG round trip at full resolution");
        Require(store.Recent().Single() == path, "Shelf found exported PNG");
        var files = LocalStore.FileDragData(path).GetData(DataFormats.FileDrop) as string[];
        Require(files is [var pngPath] && pngPath == path, "FileDrop payload contains PNG path");

        LocalStore.CopyImage(restored);
        var clipboard = Clipboard.GetDataObject();
        using var stream = clipboard?.GetData("PNG", false) as Stream;
        Require(stream is not null, "Clipboard PNG format is available");
        var png = new PngBitmapDecoder(stream!, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        Require(Pixel(png, 108, 32).R == blurred, "Clipboard PNG has edited pixels");
        Require(Clipboard.GetImage()?.PixelWidth == 150, "Clipboard image format is available");
        File.Delete(path);
        Console.WriteLine("PASS arrow, text, regional blur, undo, PNG overwrite, clipboard, shelf, FileDrop payload");

        var saved = new HotKey(true, true, true, Key.F8);
        var reserved = new HotKey(true, true, true, Key.F9);
        using var first = new HwndSource(new HwndSourceParameters("Hotkey check"));
        using var second = new HwndSource(new HwndSourceParameters("Hotkey conflict check"));
        using (var registration = new HotKeyRegistration(first, () => { }))
        using (var competing = new HotKeyRegistration(second, () => { }))
        {
            Require(registration.TrySet(saved), "Registered test hotkey");
            Require(competing.TrySet(reserved), "Registered competing hotkey");
            Require(!registration.TrySet(reserved) && registration.Current == saved,
                "Registration retained existing hotkey after conflict");
        }
        store.SaveHotKey(saved);
        Require(store.LoadHotKey() == saved, "Hotkey setting round trip");
        Console.WriteLine("PASS Win32 hotkey registration, conflict recovery, persisted setting");

        var home = new MainWindow(store);
        home.Show();
        await CheckDesktopCaptureAsync(app, home, store);

        var target = new Window
        {
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Background = Brushes.White
        };
        target.Show();
        await CheckShelfDragAsync(home, target, store.Recent().Single());
    }

    private static async Task CheckDesktopCaptureAsync(App app, MainWindow home, LocalStore store)
    {
        var primary = Native.Monitors().Single(rect => rect.X <= 0 && rect.X + rect.Width > 0 && rect.Y <= 0 && rect.Y + rect.Height > 0);
        using var left = new ScreenMarker(40, 40, 90, 190, Colors.LimeGreen);
        using var right = new ScreenMarker(130, 40, 100, 190, Colors.Tomato);
        var area = new Int32Rect(60, 65, 150, 100);
        Require(area.X + area.Width < primary.X + primary.Width && area.Y + area.Height < primary.Y + primary.Height,
            $"Primary monitor accommodates test markers ({primary})");
        var samples = new (int X, int Y, Color Expected)[]
        {
            (12, 12, Colors.LimeGreen), (118, 69, Colors.Tomato)
        };

        (Color Left, Color Right) reference = default;
        await WaitUntil(() =>
        {
            Native.DwmFlush();
            reference = (DesktopPixel(area.X + samples[0].X, area.Y + samples[0].Y),
                DesktopPixel(area.X + samples[1].X, area.Y + samples[1].Y));
            return reference == (samples[0].Expected, samples[1].Expected);
        }, () => $"The Windows desktop did not present the test markers (GetPixel: {reference})");
        Console.WriteLine($"PASS independent Windows GetPixel reference: {reference}");

        var snapshot = DesktopSnapshot.Capture().Crop(area);
        foreach (var sample in samples)
        {
            Color actual = Pixel(snapshot, sample.X, sample.Y);
            Require(actual == sample.Expected,
                $"BitBlt snapshot pixel ({sample.X},{sample.Y}) is {actual}, expected {sample.Expected}");
        }
        Console.WriteLine("PASS BitBlt copied both colors from the Windows desktop");

        MoveCursor(new Point(area.X, area.Y));
        SendKeys(0x11, 0x12, 0x10, 0x77);
        await WaitUntil(() => app.Windows.Cast<Window>().Any(window => window.IsVisible && window != home),
            "Region overlay opened via global hotkey");
        await Task.Delay(150);
        SendMouse(0x0002);
        try
        {
            await WaitUntil(() => Mouse.Captured is Window overlay && overlay != home,
                "Selection overlay received the initial mouse press");
            MoveCursor(new Point(area.X + area.Width, area.Y + area.Height));
        }
        finally
        {
            SendMouse(0x0004);
        }
        await WaitUntil(() => app.Windows.OfType<EditorWindow>().Any(window => window.IsVisible) && store.Recent().Any(),
            "Editor opened and automatically saved PNG after selection");
        var capture = LocalStore.OpenPng(store.Recent().Single());
        Require(capture.PixelWidth == area.Width && capture.PixelHeight == area.Height,
            $"Selected PNG measured {capture.PixelWidth}×{capture.PixelHeight}, expected {area.Width}×{area.Height}");
        foreach (var sample in samples)
        {
            Color actual = Pixel(capture, sample.X, sample.Y);
            Require(actual == sample.Expected,
                $"Selected PNG pixel ({sample.X},{sample.Y}) is {actual}, expected {sample.Expected}");
        }
        Console.WriteLine($"PASS desktop capture → global hotkey → mouse selection → editor → shelf PNG ({area.Width}×{area.Height}, both colors)");
        app.Windows.OfType<EditorWindow>().Single().Close();
    }

    private static async Task CheckShelfDragAsync(MainWindow home, Window target, string path)
    {
        Rect work = SystemParameters.WorkArea;
        home.Left = work.Left + 8;
        home.Top = work.Top + 12;
        home.Width = Math.Max(home.MinWidth, work.Width * 0.65);
        home.Height = Math.Max(home.MinHeight, work.Height * 0.65);
        target.Topmost = true;
        target.Left = work.Right - 190;
        target.Top = work.Top + 35;
        target.Width = 175;
        target.Height = 175;
        target.AllowDrop = true;
        string? dropped = null;
        target.Drop += (_, e) =>
        {
            dropped = (e.Data.GetData(DataFormats.FileDrop) as string[])?.SingleOrDefault();
            e.Effects = DragDropEffects.Copy;
            e.Handled = true;
        };
        home.Activate();
        await WaitUntil(() => home.Shelf.Items.Count == 1, "Shelf shows captured PNG");
        object item = home.Shelf.Items[0];
        home.Shelf.ScrollIntoView(item);
        home.UpdateLayout();
        var container = (DependencyObject?)home.Shelf.ItemContainerGenerator.ContainerFromItem(item);
        var thumbnail = container is null ? null : FindImage(container);
        if (thumbnail is null)
            throw new InvalidOperationException("Shelf thumbnail is unavailable for dragging");

        Point start = thumbnail.PointToScreen(new Point(thumbnail.ActualWidth / 2, thumbnail.ActualHeight / 2));
        Point destination = target.PointToScreen(new Point(80, 80));
        await Task.Run(async () =>
        {
            MoveCursor(start);
            await Task.Delay(100);
            SendMouse(0x0002);
            try
            {
                await Task.Delay(100);
                MoveCursor(start + new Vector(16, 0));
                await Task.Delay(200);
                MoveCursor(destination);
                await Task.Delay(250);
            }
            finally
            {
                SendMouse(0x0004);
            }
        });
        await WaitUntil(() => dropped == path, "Shelf drag delivered the PNG file to a WPF drop target");
        Console.WriteLine("PASS dragging a shelf thumbnail delivered the PNG file to another window");
    }

    private static Image? FindImage(DependencyObject parent)
    {
        if (parent is Image image)
            return image;
        for (int index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var found = FindImage(VisualTreeHelper.GetChild(parent, index));
            if (found is not null)
                return found;
        }
        return null;
    }

    private static Color DesktopPixel(int x, int y)
    {
        nint dc = GetDC(0);
        if (dc == 0)
            throw new InvalidOperationException("Could not get a desktop DC for the reference pixel.");
        try
        {
            uint color = GetPixel(dc, x, y);
            if (color == 0xFFFFFFFF)
                throw new InvalidOperationException($"Could not read the desktop reference pixel at {x},{y}.");
            return Color.FromRgb((byte)color, (byte)(color >> 8), (byte)(color >> 16));
        }
        finally
        {
            ReleaseDC(0, dc);
        }
    }

    private static Color Pixel(BitmapSource bitmap, int x, int y)
    {
        var pixel = new byte[4];
        new FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0)
            .CopyPixels(new Int32Rect(x, y, 1, 1), pixel, 4, 0);
        return Color.FromArgb(pixel[3], pixel[2], pixel[1], pixel[0]);
    }

    private static Task WaitUntil(Func<bool> test, string description) => WaitUntil(test, () => description);

    private static async Task WaitUntil(Func<bool> test, Func<string> describeFailure)
    {
        for (int attempt = 0; attempt < 100; attempt++)
        {
            if (test())
                return;
            await Task.Delay(50);
        }
        throw new InvalidOperationException(describeFailure());
    }

    private static void Require(bool result, string description)
    {
        if (!result)
            throw new InvalidOperationException(description);
    }

    private static void MoveCursor(Point point) =>
        Require(SetCursorPos((int)point.X, (int)point.Y), "Set cursor position");

    private static void SendKeys(params ushort[] keys)
    {
        var inputs = keys.Select(key => KeyInput(key, 0)).Concat(keys.Reverse().Select(key => KeyInput(key, 2))).ToArray();
        Require(SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) == inputs.Length,
            "Send keyboard input");
    }

    private static Input KeyInput(ushort key, uint flags) => new()
    {
        Type = 1, Data = new InputData { Keyboard = new KeyboardInput { Key = key, Flags = flags } }
    };

    private static void SendMouse(uint flags)
    {
        Input[] inputs = [new() { Data = new InputData { Mouse = new MouseInput { Flags = flags } } }];
        Require(SendInput(1, inputs, Marshal.SizeOf<Input>()) == 1, "Send mouse input");
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern nint GetDC(nint window);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(nint window, nint dc);

    [DllImport("gdi32.dll")]
    private static extern uint GetPixel(nint dc, int x, int y);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputData Data;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputData
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int X, Y;
        public uint Data, Flags, Time;
        public nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort Key, ScanCode;
        public uint Flags, Time;
        public nuint ExtraInfo;
    }
}
