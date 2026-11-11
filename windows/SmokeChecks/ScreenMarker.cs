using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Media;

internal sealed class ScreenMarker : IDisposable
{
    private static readonly WindowProcedure Procedure = DefWindowProcW;
    private static readonly nint Instance = GetModuleHandleW(null);
    private readonly string className = $"ScreenshotAppSmokeMarker-{Guid.NewGuid():N}";
    private readonly nint window;

    internal ScreenMarker(int x, int y, int width, int height, Color color)
    {
        uint colorRef = (uint)(color.R | color.G << 8 | color.B << 16);
        nint brush = CreateSolidBrush(colorRef);
        if (brush == 0)
            throw new InvalidOperationException("Could not create the desktop marker brush.");

        var windowClass = new WindowClass
        {
            WindowProcedure = Marshal.GetFunctionPointerForDelegate(Procedure),
            Instance = Instance,
            Background = brush,
            ClassName = className
        };
        if (RegisterClassW(ref windowClass) == 0)
        {
            var error = new Win32Exception();
            DeleteObject(brush);
            throw error;
        }

        const uint topmostToolWindow = 0x00000008 | 0x00000080;
        const uint visiblePopup = 0x80000000 | 0x10000000;
        window = CreateWindowExW(topmostToolWindow, className, "ScreenshotApp smoke marker",
            visiblePopup, x, y, width, height, 0, 0, Instance, 0);
        if (window == 0)
        {
            var error = new Win32Exception();
            Dispose();
            throw error;
        }

        const uint paintNowWithBackground = 0x0001 | 0x0004 | 0x0100;
        RedrawWindow(window, 0, 0, paintNowWithBackground);
    }

    public void Dispose()
    {
        if (window != 0)
            DestroyWindow(window);
        UnregisterClassW(className, Instance);
    }

    private delegate nint WindowProcedure(nint window, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Style;
        public nint WindowProcedure;
        public int ClassExtra, WindowExtra;
        public nint Instance, Icon, Cursor, Background, MenuName;
        public string ClassName;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern nint GetModuleHandleW(string? module);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern ushort RegisterClassW(ref WindowClass windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int UnregisterClassW(string className, nint instance);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern nint CreateWindowExW(uint extendedStyle, string className, string title, uint style,
        int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);

    [DllImport("user32.dll")]
    private static extern int RedrawWindow(nint window, nint rect, nint region, uint flags);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern nint DefWindowProcW(nint window, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern int DestroyWindow(nint window);

    [DllImport("gdi32.dll")]
    private static extern nint CreateSolidBrush(uint color);

    [DllImport("gdi32.dll")]
    private static extern int DeleteObject(nint handle);
}
