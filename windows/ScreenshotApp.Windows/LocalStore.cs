using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media.Imaging;

namespace ScreenshotApp.Windows;

internal sealed class LocalStore
{
    private readonly string settingsPath;
    internal string CaptureDirectory { get; }

    internal LocalStore(string? root = null)
    {
        root ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ScreenshotApp-Bogdan");
        settingsPath = Path.Combine(root, "hotkey.json");
        CaptureDirectory = Path.Combine(root, "Captures");
    }

    internal HotKey LoadHotKey()
    {
        if (!File.Exists(settingsPath))
            return HotKey.Default;
        try
        {
            var key = JsonSerializer.Deserialize<HotKey>(File.ReadAllText(settingsPath));
            return key is { IsValid: true } ? key : HotKey.Default;
        }
        catch (JsonException)
        {
            return HotKey.Default;
        }
    }

    internal void SaveHotKey(HotKey key) =>
        WriteAtomically(settingsPath, stream => JsonSerializer.Serialize(stream, key));

    internal string NewCapturePath()
    {
        string name = $"Screenshot-{DateTime.Now:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}";
        return Path.Combine(CaptureDirectory, name[..38] + ".png");
    }

    internal static void SavePng(string path, BitmapSource bitmap) =>
        WriteAtomically(path, stream => EncodePng(stream, bitmap));

    internal IEnumerable<string> Recent() =>
        Directory.Exists(CaptureDirectory)
            ? Directory.EnumerateFiles(CaptureDirectory, "Screenshot-*.png")
                .OrderByDescending(Path.GetFileName, StringComparer.Ordinal).Take(20)
            : [];

    internal static BitmapImage OpenPng(string path, int thumbnailWidth = 0)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = file;
        if (thumbnailWidth > 0)
            bitmap.DecodePixelWidth = thumbnailWidth;
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    internal static void CopyImage(BitmapSource bitmap)
    {
        using var png = new MemoryStream();
        EncodePng(png, bitmap);
        png.Position = 0;
        var data = new DataObject();
        data.SetData(DataFormats.Bitmap, bitmap);
        data.SetData("PNG", png, false);
        Clipboard.SetDataObject(data, true);
    }

    internal static DataObject FileDragData(string path) => new(DataFormats.FileDrop, new[] { path });

    private static void EncodePng(Stream output, BitmapSource bitmap)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        encoder.Save(output);
    }

    private static void WriteAtomically(string path, Action<Stream> write)
    {
        string directory = Path.GetDirectoryName(Path.GetFullPath(path))!;
        Directory.CreateDirectory(directory);
        string temp = Path.Combine(directory, $".{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                write(stream);
            File.Move(temp, path, true);
        }
        finally
        {
            File.Delete(temp);
        }
    }
}
