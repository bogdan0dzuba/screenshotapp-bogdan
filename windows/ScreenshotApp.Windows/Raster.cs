using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ScreenshotApp.Windows;

internal static class Raster
{
    internal static BitmapSource Render(int width, int height, Action<DrawingContext> draw)
    {
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
            draw(context);
        var rendered = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        rendered.Render(visual);
        rendered.Freeze();
        return rendered;
    }

    internal static BitmapSource Blur(BitmapSource source, Int32Rect area)
    {
        var region = new CroppedBitmap(source, area);
        int width = region.PixelWidth;
        int height = region.PixelHeight;
        int stride = checked(width * 4);
        var pixels = new byte[checked(stride * height)];
        new FormatConvertedBitmap(region, PixelFormats.Bgr32, null, 0).CopyPixels(pixels, stride, 0);
        var buffer = new byte[pixels.Length];
        int radius = Math.Clamp(Math.Min(width, height) / 5, 2, 24);

        BoxPass(pixels, buffer, height, width, stride, 4, radius);
        BoxPass(buffer, pixels, width, height, 4, stride, radius);
        BoxPass(pixels, buffer, height, width, stride, 4, radius);
        BoxPass(buffer, pixels, width, height, 4, stride, radius);

        var result = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgr32, null, pixels, stride);
        result.Freeze();
        return result;
    }

    private static void BoxPass(byte[] input, byte[] output, int lines, int length, int lineStep, int pixelStep,
        int radius)
    {
        int samples = 2 * radius + 1;
        for (int line = 0; line < lines; line++)
        {
            int start = line * lineStep;
            for (int channel = 0; channel < 3; channel++)
            {
                int offset = start + channel;
                int sum = 0;
                for (int sample = -radius; sample <= radius; sample++)
                    sum += input[offset + Math.Clamp(sample, 0, length - 1) * pixelStep];

                for (int index = 0; index < length; index++)
                {
                    output[offset + index * pixelStep] = (byte)(sum / samples);
                    int leaving = Math.Max(index - radius, 0);
                    int entering = Math.Min(index + radius + 1, length - 1);
                    sum += input[offset + entering * pixelStep] - input[offset + leaving * pixelStep];
                }
            }
        }
    }
}

internal sealed class ScreenshotDocument(BitmapSource original)
{
    private readonly List<Action<DrawingContext>> edits = [];
    internal int Width => original.PixelWidth;
    internal int Height => original.PixelHeight;
    internal bool CanUndo => edits.Count != 0;

    internal BitmapSource Render() => edits.Count == 0 ? original : Raster.Render(Width, Height, Draw);

    internal void Draw(DrawingContext drawing)
    {
        drawing.DrawImage(original, new Rect(0, 0, Width, Height));
        foreach (var edit in edits)
            edit(drawing);
    }

    internal void AddArrow(Point start, Point end) =>
        edits.Add(drawing => DrawArrow(drawing, start, end, AnnotationSize));

    internal void AddText(Point anchor, string text)
    {
        double margin = AnnotationSize * 0.35;
        var label = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface("Segoe UI"), AnnotationSize * 1.15, Brushes.White, 1.0)
        {
            MaxTextWidth = Math.Max(1, Width - 2 * margin)
        };
        double x = Math.Clamp(anchor.X, 0, Math.Max(0, Width - label.Width - 2 * margin));
        double y = Math.Clamp(anchor.Y, 0, Math.Max(0, Height - label.Height - 2 * margin));
        var background = new Rect(x, y, label.Width + 2 * margin, label.Height + 2 * margin);
        edits.Add(drawing =>
        {
            drawing.DrawRoundedRectangle(Brushes.Black, null, background, margin, margin);
            drawing.DrawText(label, new Point(x + margin, y + margin));
        });
    }

    internal void AddBlur(Rect selection)
    {
        int x = Math.Max(0, (int)Math.Floor(selection.Left));
        int y = Math.Max(0, (int)Math.Floor(selection.Top));
        int right = Math.Min(Width, (int)Math.Ceiling(selection.Right));
        int bottom = Math.Min(Height, (int)Math.Ceiling(selection.Bottom));
        if (right <= x || bottom <= y)
            return;
        var area = new Int32Rect(x, y, right - x, bottom - y);
        var blurred = Raster.Blur(Render(), area);
        edits.Add(drawing => drawing.DrawImage(blurred, DesktopSnapshot.ToRect(area)));
    }

    internal void Undo()
    {
        if (CanUndo)
            edits.RemoveAt(edits.Count - 1);
    }

    internal double AnnotationSize => Math.Clamp(Math.Min(Width, Height) / 24.0, 12, 44);

    internal static void DrawArrow(DrawingContext drawing, Point start, Point end, double size)
    {
        Vector direction = end - start;
        double length = direction.Length;
        if (length < 2)
            return;

        direction.Normalize();
        var normal = new Vector(-direction.Y, direction.X);
        double headSize = Math.Min(size * 0.85, length * 0.65);
        double strokeWidth = Math.Max(2, Math.Min(size * 0.23, length * 0.2));
        Point headBase = end - direction * headSize;
        var color = Brushes.OrangeRed;
        drawing.DrawLine(new Pen(Brushes.Black, strokeWidth + 2), start, headBase);
        drawing.DrawLine(new Pen(color, strokeWidth), start, headBase);

        var tip = new StreamGeometry();
        using (var path = tip.Open())
        {
            path.BeginFigure(end, true, true);
            path.LineTo(headBase + normal * (headSize * 0.54), true, false);
            path.LineTo(headBase - normal * (headSize * 0.54), true, false);
        }
        drawing.DrawGeometry(color, new Pen(Brushes.Black, 1), tip);
    }
}
