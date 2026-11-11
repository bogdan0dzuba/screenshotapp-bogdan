using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ScreenshotApp.Windows;

internal static class Native
{
    internal const int HotKeyMessage = 0x0312;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint key);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(nint window, int id);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out ScreenPoint point);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorCallback callback, nint data);

    [DllImport("user32.dll")]
    private static extern nint GetDC(nint window);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(nint window, nint dc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern nint CreateCompatibleDC(nint dc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern nint CreateDIBSection(nint dc, ref BitmapHeader header, uint colors,
        out nint pixels, nint section, uint offset);

    [DllImport("gdi32.dll")]
    private static extern nint SelectObject(nint dc, nint obj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(nint obj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteDC(nint dc);

    [DllImport("gdi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BitBlt(nint dest, int x, int y, int width, int height,
        nint source, int sourceX, int sourceY, uint operation);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GdiFlush();

    [DllImport("dwmapi.dll")]
    internal static extern int DwmFlush();

    internal static Point CursorPosition()
    {
        if (!GetCursorPos(out var point))
            throw new Win32Exception();
        return new Point(point.X, point.Y);
    }

    internal static void PlaceOverlay(nint window, Int32Rect rect)
    {
        const uint noActivate = 0x0010;
        if (!SetWindowPos(window, -1, rect.X, rect.Y, rect.Width, rect.Height, noActivate))
            throw new Win32Exception();
    }

    internal static IReadOnlyList<Int32Rect> Monitors()
    {
        var monitors = new List<Int32Rect>();
        bool AddMonitor(nint monitor, nint dc, ref ScreenRect rect, nint data)
        {
            monitors.Add(new Int32Rect(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top));
            return true;
        }

        if (!EnumDisplayMonitors(0, 0, AddMonitor, 0) || monitors.Count == 0)
            throw new InvalidOperationException("Windows не вернула список экранов.");
        return monitors;
    }

    internal static BitmapSource Capture(Int32Rect rect)
    {
        nint screen = GetDC(0);
        if (screen == 0)
            throw new InvalidOperationException("Не удалось получить доступ к рабочему столу.");

        nint memory = 0;
        nint bitmap = 0;
        nint previous = 0;
        try
        {
            memory = CreateCompatibleDC(screen);
            if (memory == 0)
                throw new Win32Exception();

            var header = new BitmapHeader
            {
                Size = (uint)Marshal.SizeOf<BitmapHeader>(),
                Width = rect.Width,
                Height = -rect.Height,
                Planes = 1,
                BitsPerPixel = 32
            };
            bitmap = CreateDIBSection(screen, ref header, 0, out nint pixels, 0, 0);
            if (bitmap == 0)
                throw new Win32Exception();

            previous = SelectObject(memory, bitmap);
            if (previous == 0 || previous == -1)
                throw new InvalidOperationException("Не удалось подготовить буфер захвата.");

            const uint sourceCopy = 0x00CC0020;
            const uint includeLayeredWindows = 0x40000000;
            if (!BitBlt(memory, 0, 0, rect.Width, rect.Height, screen, rect.X, rect.Y,
                    sourceCopy | includeLayeredWindows))
                throw new Win32Exception();
            if (!GdiFlush())
                throw new InvalidOperationException("Windows не завершила копирование экрана.");

            int stride = checked(rect.Width * 4);
            var buffer = new byte[checked(stride * rect.Height)];
            Marshal.Copy(pixels, buffer, 0, buffer.Length);
            var frame = BitmapSource.Create(rect.Width, rect.Height, 96, 96, PixelFormats.Bgr32, null, buffer, stride);
            frame.Freeze();
            return frame;
        }
        finally
        {
            if (previous != 0 && previous != -1)
                SelectObject(memory, previous);
            if (bitmap != 0)
                DeleteObject(bitmap);
            if (memory != 0)
                DeleteDC(memory);
            ReleaseDC(0, screen);
        }
    }

    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool MonitorCallback(nint monitor, nint dc, ref ScreenRect rect, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private struct ScreenPoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ScreenRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitsPerPixel;
        public uint Compression;
        public uint ImageSize;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ColorsUsed;
        public uint ColorsImportant;
    }
}
