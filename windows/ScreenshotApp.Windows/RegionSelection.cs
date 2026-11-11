using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ScreenshotApp.Windows;

internal sealed record ScreenFrame(Int32Rect Bounds, BitmapSource Image);

internal sealed class DesktopSnapshot(IReadOnlyList<ScreenFrame> frames)
{
    internal IReadOnlyList<ScreenFrame> Frames => frames;

    internal static DesktopSnapshot Capture() =>
        new(Native.Monitors().Select(bounds => new ScreenFrame(bounds, Native.Capture(bounds))).ToArray());

    internal BitmapSource Crop(Int32Rect area)
    {
        foreach (var frame in frames)
        {
            var overlap = Rect.Intersect(ToRect(frame.Bounds), ToRect(area));
            if (overlap == ToRect(area))
            {
                var cropped = new CroppedBitmap(frame.Image,
                    new Int32Rect(area.X - frame.Bounds.X, area.Y - frame.Bounds.Y, area.Width, area.Height));
                cropped.Freeze();
                return cropped;
            }
        }

        return Raster.Render(area.Width, area.Height, drawing =>
        {
            drawing.DrawRectangle(Brushes.Black, null, new Rect(0, 0, area.Width, area.Height));
            foreach (var frame in frames)
            {
                var bounds = frame.Bounds;
                drawing.DrawImage(frame.Image,
                    new Rect(bounds.X - area.X, bounds.Y - area.Y, bounds.Width, bounds.Height));
            }
        });
    }

    internal static Rect ToRect(Int32Rect pixels) => new(pixels.X, pixels.Y, pixels.Width, pixels.Height);
}

internal sealed class RegionSelection
{
    private readonly DesktopSnapshot desktop;
    private readonly List<Overlay> overlays = [];
    private readonly TaskCompletionSource<Int32Rect?> completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private Point? start;
    private bool finished;

    internal RegionSelection(DesktopSnapshot desktop) => this.desktop = desktop;

    internal async Task<Int32Rect?> SelectAsync()
    {
        try
        {
            Point cursor = Native.CursorPosition();
            foreach (var frame in desktop.Frames)
            {
                var overlay = new Overlay(this, frame);
                overlays.Add(overlay);
                overlay.Show();
                overlay.Place();
            }

            var active = overlays.FirstOrDefault(window => DesktopSnapshot.ToRect(window.Bounds).Contains(cursor));
            (active ?? overlays[0]).Activate();
            return await completion.Task;
        }
        finally
        {
            finished = true;
            foreach (var overlay in overlays)
            {
                if (overlay.IsVisible)
                    overlay.Close();
            }
        }
    }

    private void Start(Overlay overlay)
    {
        if (finished || start.HasValue)
            return;

        start = Native.CursorPosition();
        if (!Mouse.Capture(overlay))
            Finish(null);
    }

    private void Move()
    {
        if (finished || start is not Point origin)
            return;

        var area = new Rect(origin, Native.CursorPosition());
        foreach (var overlay in overlays)
            overlay.SetSelection(area);
    }

    private void End()
    {
        if (finished || start is not Point origin)
            return;

        var rect = new Rect(origin, Native.CursorPosition());
        Int32Rect? result = rect.Width >= 2 && rect.Height >= 2
            ? new Int32Rect((int)rect.X, (int)rect.Y, (int)rect.Width, (int)rect.Height)
            : null;
        Finish(result);
        Mouse.Capture(null);
    }

    private void Finish(Int32Rect? result)
    {
        if (finished)
            return;
        finished = true;
        completion.TrySetResult(result);
    }

    private sealed class Overlay : Window
    {
        private readonly OverlaySurface surface;
        internal Int32Rect Bounds { get; }

        internal Overlay(RegionSelection session, ScreenFrame frame)
        {
            Bounds = frame.Bounds;
            surface = new OverlaySurface(frame);
            Content = surface;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = true;
            Cursor = Cursors.Cross;
            Background = Brushes.Black;
            Left = Bounds.X;
            Top = Bounds.Y;
            Width = Bounds.Width;
            Height = Bounds.Height;
            SourceInitialized += (_, _) => Place();
            PreviewMouseLeftButtonDown += (_, e) => { session.Start(this); e.Handled = true; };
            PreviewMouseMove += (_, _) => session.Move();
            PreviewMouseLeftButtonUp += (_, e) => { session.End(); e.Handled = true; };
            LostMouseCapture += (_, _) => session.Finish(null);
            PreviewMouseRightButtonDown += (_, _) => session.Finish(null);
            PreviewKeyDown += (_, e) =>
            {
                if (e.Key == Key.Escape)
                {
                    session.Finish(null);
                    e.Handled = true;
                }
            };
            Closed += (_, _) => session.Finish(null);
        }

        internal void Place() => Native.PlaceOverlay(new WindowInteropHelper(this).Handle, Bounds);

        internal void SetSelection(Rect selection)
        {
            surface.Selection = selection;
            surface.InvalidateVisual();
        }
    }

    private sealed class OverlaySurface(ScreenFrame frame) : FrameworkElement
    {
        private static readonly Brush Shade = CreateShade();
        private static readonly Pen Outline = new(Brushes.White, 1);
        internal Rect Selection { get; set; } = Rect.Empty;

        protected override void OnRender(DrawingContext drawing)
        {
            var viewport = new Rect(RenderSize);
            drawing.DrawImage(frame.Image, viewport);
            if (Selection.IsEmpty)
            {
                drawing.DrawRectangle(Shade, null, viewport);
                return;
            }

            double scaleX = RenderSize.Width / frame.Bounds.Width;
            double scaleY = RenderSize.Height / frame.Bounds.Height;
            var selected = new Rect((Selection.X - frame.Bounds.X) * scaleX,
                (Selection.Y - frame.Bounds.Y) * scaleY, Selection.Width * scaleX, Selection.Height * scaleY);

            drawing.PushClip(new RectangleGeometry(viewport));
            drawing.DrawGeometry(Shade, null, new CombinedGeometry(GeometryCombineMode.Exclude,
                new RectangleGeometry(viewport), new RectangleGeometry(selected)));
            drawing.DrawRectangle(null, Outline, selected);
            drawing.Pop();
        }

        private static Brush CreateShade()
        {
            var brush = new SolidColorBrush(Color.FromArgb(148, 8, 13, 25));
            brush.Freeze();
            return brush;
        }
    }
}
