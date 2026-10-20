using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace Babelstaarnet.Windows;

// Put the effect behind the panel. Applying it to the content border makes
// WPF rasterize and rescale its text, which blurs small type at high DPI.
internal sealed class FloatingSurface : Grid
{
    public FloatingSurface(Border panel)
    {
        Children.Add(new Border { Background = Brushes.White, CornerRadius = panel.CornerRadius,
            IsHitTestVisible = false, Effect = new DropShadowEffect
            { Color = Colors.Black, BlurRadius = 22, ShadowDepth = 5, Opacity = .14 } });
        Children.Add(panel);
        UseLayoutRounding = true;
    }
}
