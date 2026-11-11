using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace ScreenshotApp.Windows;

public partial class MainWindow : Window
{
    private readonly LocalStore store;
    private HotKeyRegistration? hotKey;
    private bool selecting;
    private bool closed;
    private (FrameworkElement Source, Point Start)? drag;

    internal MainWindow(LocalStore store)
    {
        this.store = store;
        InitializeComponent();
        TriggerKey.ItemsSource = HotKey.Choices;
        SourceInitialized += InitializeHotKey;
        Activated += (_, _) => ReportErrors(RefreshShelf);
        ReportErrors(RefreshShelf);
    }

    private void InitializeHotKey(object? sender, EventArgs e)
    {
        var source = (HwndSource)PresentationSource.FromVisual(this);
        hotKey = new HotKeyRegistration(source, () => _ = CaptureAsync(hideHome: false));
        ShowHotKey(HotKey.Default);
        ReportErrors(() =>
        {
            var saved = store.LoadHotKey();
            ShowHotKey(saved);
            Status.Text = hotKey.TrySet(saved)
                ? $"Активный хоткей · {saved}"
                : "Хоткей занят или зарезервирован. Выберите другую комбинацию.";
        });
    }

    private void ShowHotKey(HotKey key)
    {
        Ctrl.IsChecked = key.Ctrl;
        Alt.IsChecked = key.Alt;
        Shift.IsChecked = key.Shift;
        TriggerKey.SelectedItem = key.Key;
    }

    private void ApplyHotKey(object sender, RoutedEventArgs e)
    {
        if (hotKey is null || TriggerKey.SelectedItem is not Key trigger)
            return;
        var key = new HotKey(Ctrl.IsChecked == true, Alt.IsChecked == true, Shift.IsChecked == true, trigger);
        if (!key.IsValid)
        {
            Status.Text = "Добавьте Ctrl, Alt или Shift.";
            return;
        }
        if (!hotKey.TrySet(key))
        {
            Status.Text = hotKey.Current is HotKey active
                ? $"Комбинация занята. Активный хоткей · {active}"
                : "Хоткей занят или зарезервирован. Выберите другую комбинацию.";
            return;
        }

        ReportErrors(() =>
        {
            store.SaveHotKey(key);
            Status.Text = $"Активный хоткей · {key}";
        }, $"Хоткей {key} работает. Сохранить его не удалось");
    }

    private async void CaptureClick(object sender, RoutedEventArgs e) => await CaptureAsync(hideHome: true);

    private async Task CaptureAsync(bool hideHome)
    {
        if (selecting || closed)
            return;
        selecting = true;
        bool opened = false;
        try
        {
            if (hideHome)
            {
                WindowState = WindowState.Minimized;
                await Dispatcher.InvokeAsync(() => Native.DwmFlush(), DispatcherPriority.ApplicationIdle);
            }

            var snapshot = await Task.Run(DesktopSnapshot.Capture);
            if (closed)
                return;
            var area = await new RegionSelection(snapshot).SelectAsync();
            if (area is null || closed)
                return;

            var editor = new EditorWindow(snapshot.Crop(area.Value), store.NewCapturePath(),
                () => ReportErrors(RefreshShelf));
            editor.Show();
            editor.Activate();
            opened = true;
        }
        catch (Exception error) when (IsOperationError(error))
        {
            Status.Text = $"Не удалось сделать снимок. {error.Message}";
            if (WindowState == WindowState.Minimized && !closed)
                WindowState = WindowState.Normal;
        }
        finally
        {
            if (hideHome && !opened && !closed)
                WindowState = WindowState.Normal;
            selecting = false;
        }
    }

    private void RefreshShelf()
    {
        var recent = new List<ShelfEntry>();
        foreach (string path in store.Recent())
        {
            try
            {
                recent.Add(new ShelfEntry(path, Path.GetFileName(path), LocalStore.OpenPng(path, 192)));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                                                 FileFormatException or NotSupportedException or ArgumentException)
            {
                // A deleted, unreadable or damaged file must not block other captures.
            }
        }
        Shelf.ItemsSource = recent;
        EmptyShelf.Visibility = recent.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OpenFolder(object sender, RoutedEventArgs e) => ReportErrors(() =>
    {
        Directory.CreateDirectory(store.CaptureDirectory);
        Process.Start(new ProcessStartInfo(store.CaptureDirectory) { UseShellExecute = true });
    });

    private void CopyRecent(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is ShelfEntry item)
            ReportErrors(() =>
            {
                LocalStore.CopyImage(LocalStore.OpenPng(item.Path));
                Status.Text = "PNG скопирован.";
            });
    }

    private void StartFileDrag(object sender, MouseButtonEventArgs e) =>
        drag = ((FrameworkElement)sender, e.GetPosition(this));

    private void EndFileDrag(object sender, MouseButtonEventArgs e) => drag = null;

    private void MoveFileDrag(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed)
        {
            drag = null;
            return;
        }
        if (drag is not { } gesture || gesture.Source != sender || gesture.Source.DataContext is not ShelfEntry item)
            return;
        Vector offset = e.GetPosition(this) - gesture.Start;
        if (Math.Abs(offset.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(offset.Y) < SystemParameters.MinimumVerticalDragDistance)
            return;

        drag = null;
        ReportErrors(() =>
        {
            if (!File.Exists(item.Path))
            {
                RefreshShelf();
                Status.Text = "Файл снимка был перемещен или удален.";
                return;
            }
            DragDrop.DoDragDrop(gesture.Source, LocalStore.FileDragData(item.Path), DragDropEffects.Copy);
        });
    }

    private void ReportErrors(Action operation, string action = "Операция не выполнена")
    {
        try { operation(); }
        catch (Exception error) when (IsOperationError(error))
        {
            Status.Text = $"{action}. {error.Message}";
        }
    }

    internal static bool IsOperationError(Exception error) =>
        error is IOException or UnauthorizedAccessException or ExternalException or InvalidOperationException
            or NotSupportedException or ArgumentException or Win32Exception or OverflowException;

    protected override void OnClosed(EventArgs e)
    {
        closed = true;
        hotKey?.Dispose();
        base.OnClosed(e);
    }

    private sealed record ShelfEntry(string Path, string Name, BitmapSource Thumbnail);
}
