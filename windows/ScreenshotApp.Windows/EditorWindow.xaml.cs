using Microsoft.Win32;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ScreenshotApp.Windows;

public partial class EditorWindow : Window
{
    private readonly ScreenshotDocument document;
    private readonly string capturePath;
    private readonly Action shelfChanged;
    private readonly EditorSurface surface;
    private Point? start;
    private Tool gestureTool;

    internal EditorWindow(BitmapSource image, string capturePath, Action shelfChanged)
    {
        document = new ScreenshotDocument(image);
        this.capturePath = capturePath;
        this.shelfChanged = shelfChanged;
        InitializeComponent();
        surface = new EditorSurface(document);
        Preview.Child = surface;
        surface.MouseLeftButtonDown += BeginEdit;
        surface.MouseMove += UpdateEdit;
        surface.MouseLeftButtonUp += FinishEdit;
        surface.LostMouseCapture += (_, _) => ClearGesture();
        Dimensions.Text = $"{document.Width} × {document.Height} px";
        Bind(Key.Z, Undo);
        Bind(Key.C, Copy);
        Bind(Key.S, Save);
        ContentRendered += SaveInitialCapture;
        UndoButton.IsEnabled = false;
    }

    private void SaveInitialCapture(object? sender, EventArgs e)
    {
        ContentRendered -= SaveInitialCapture;
        UpdateShelf();
    }

    private void Bind(Key key, Action action)
    {
        var command = new RoutedCommand();
        InputBindings.Add(new KeyBinding(command, key, ModifierKeys.Control));
        CommandBindings.Add(new CommandBinding(command, (_, _) => action()));
    }

    private void BeginEdit(object sender, MouseButtonEventArgs e)
    {
        Point point = Clamp(e.GetPosition(surface));
        if (TextTool.IsChecked == true)
        {
            string? text = ReadText();
            if (!string.IsNullOrWhiteSpace(text))
                Try(() => { document.AddText(point, text.Trim()); UpdateShelf(); });
            return;
        }

        start = point;
        gestureTool = BlurTool.IsChecked == true ? Tool.Blur : Tool.Arrow;
        if (!surface.CaptureMouse())
            ClearGesture();
        e.Handled = true;
    }

    private void UpdateEdit(object sender, MouseEventArgs e)
    {
        if (start is Point origin)
        {
            surface.Gesture = (gestureTool, origin, Clamp(e.GetPosition(surface)));
            surface.InvalidateVisual();
        }
    }

    private void FinishEdit(object sender, MouseButtonEventArgs e)
    {
        if (start is not Point origin)
            return;

        Point end = Clamp(e.GetPosition(surface));
        var area = new Rect(origin, end);
        var tool = gestureTool;
        ClearGesture();
        surface.ReleaseMouseCapture();
        e.Handled = true;

        Try(() =>
        {
            if (tool == Tool.Blur && area.Width >= 2 && area.Height >= 2)
                document.AddBlur(area);
            else if (tool == Tool.Arrow && (end - origin).Length >= 2)
                document.AddArrow(origin, end);
            else
                return;
            UpdateShelf();
        });
    }

    private void ClearGesture()
    {
        start = null;
        surface.Gesture = null;
        surface.InvalidateVisual();
    }

    private Point Clamp(Point point) =>
        new(Math.Clamp(point.X, 0, document.Width), Math.Clamp(point.Y, 0, document.Height));

    private void UndoClick(object sender, RoutedEventArgs e) => Undo();
    private void CopyClick(object sender, RoutedEventArgs e) => Copy();
    private void SaveClick(object sender, RoutedEventArgs e) => Save();

    private void Undo()
    {
        if (!document.CanUndo)
            return;
        document.Undo();
        UpdateShelf();
    }

    private void UpdateShelf()
    {
        surface.InvalidateVisual();
        UndoButton.IsEnabled = document.CanUndo;
        Try(() =>
        {
            LocalStore.SavePng(capturePath, document.Render());
            shelfChanged();
            Status.Text = "PNG сохранен на полке.";
        }, "Не удалось обновить PNG на полке");
    }

    private void Copy() => Try(() =>
    {
        LocalStore.CopyImage(document.Render());
        Status.Text = "PNG скопирован.";
    });

    private void Save() => Try(() =>
    {
        var dialog = new SaveFileDialog
        {
            Filter = "PNG (*.png)|*.png",
            DefaultExt = ".png",
            AddExtension = true,
            FileName = Path.GetFileName(capturePath)
        };
        if (dialog.ShowDialog(this) == true)
        {
            LocalStore.SavePng(dialog.FileName, document.Render());
            Status.Text = $"Сохранено в {dialog.FileName}";
        }
    });

    private void Try(Action action, string message = "Операция не выполнена")
    {
        try { action(); }
        catch (Exception error) when (MainWindow.IsOperationError(error))
        {
            Status.Text = $"{message}. {error.Message}";
        }
    }

    private string? ReadText()
    {
        var field = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MaxLength = 1000
        };
        System.Windows.Automation.AutomationProperties.SetName(field, "Текст на снимке");
        var ok = new Button { Content = "Добавить", IsDefault = true, Margin = new Thickness(8, 0, 0, 0) };
        var cancel = new Button { Content = "Отмена", IsCancel = true };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(cancel);
        buttons.Children.Add(ok);
        var layout = new DockPanel { Margin = new Thickness(14) };
        DockPanel.SetDock(buttons, Dock.Bottom);
        buttons.Margin = new Thickness(0, 12, 0, 0);
        layout.Children.Add(buttons);
        layout.Children.Add(field);
        var dialog = new Window
        {
            Owner = this, Title = "Текст на снимке", Width = 430, Height = 235,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, ShowInTaskbar = false,
            Content = layout
        };
        dialog.Loaded += (_, _) => field.Focus();
        ok.Click += (_, _) => dialog.DialogResult = true;
        return dialog.ShowDialog() == true ? field.Text : null;
    }

    private enum Tool { Arrow, Blur }

    private sealed class EditorSurface : FrameworkElement
    {
        private readonly ScreenshotDocument document;
        internal (Tool Tool, Point Start, Point End)? Gesture { get; set; }

        internal EditorSurface(ScreenshotDocument document)
        {
            this.document = document;
            Width = document.Width;
            Height = document.Height;
            Cursor = Cursors.Cross;
            ClipToBounds = true;
        }

        protected override void OnRender(DrawingContext drawing)
        {
            document.Draw(drawing);
            if (Gesture is not { } gesture)
                return;
            if (gesture.Tool == Tool.Arrow)
                ScreenshotDocument.DrawArrow(drawing, gesture.Start, gesture.End, document.AnnotationSize);
            else
                drawing.DrawRectangle(null, new Pen(Brushes.DeepSkyBlue, 2), new Rect(gesture.Start, gesture.End));
        }
    }
}
