using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;

namespace Babelstaarnet.Windows;

// Windows settings use a navigation rail and one focused page, while the
// underlying grouped form can still be rendered and tested on its own.
internal sealed class SettingsShell : Grid
{
    private readonly SettingsPanel panel;
    private readonly TextBlock title = Ui.Text("Settings", 28, true);
    internal string SelectedPage { get; private set; } = "Translation";
    internal SettingsShell(ReaderUiModel model)
    {
        Background = Ui.Paper; WindowsTheme.Current.AddResources(Resources);
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(210) });
        ColumnDefinitions.Add(new ColumnDefinition());
        var rail = new DockPanel { Margin = new Thickness(16, 22, 14, 18) };
        var brand = new StackPanel { Margin = new Thickness(8, 0, 0, 24) };
        brand.Children.Add(new Image { Source = BrandIcons.AppImage, Width = 38, Height = 38, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 12) });
        brand.Children.Add(Ui.Text("Babelstårnet", 17, true)); var sub = Ui.Text("Read Danish, naturally", 11); sub.Foreground = Ui.Muted; brand.Children.Add(sub);
        DockPanel.SetDock(brand, Dock.Top); rail.Children.Add(brand);
        var navigation = new ListBox { Background = System.Windows.Media.Brushes.Transparent, BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
        System.Windows.Automation.AutomationProperties.SetName(navigation, "Settings pages");
        var itemStyle = (Style)XamlReader.Parse("""
            <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ListBoxItem">
              <Setter Property="Foreground" Value="{DynamicResource Babel.Ink}"/>
              <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
                <Border x:Name="surface" CornerRadius="6" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" Padding="{TemplateBinding Padding}">
                  <ContentPresenter VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsSelected" Value="True"><Setter TargetName="surface" Property="Background" Value="{DynamicResource Babel.AccentSoft}"/><Setter TargetName="surface" Property="BorderBrush" Value="{DynamicResource Babel.Accent}"/></Trigger>
                  <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="surface" Property="BorderBrush" Value="{DynamicResource Babel.Accent}"/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate></Setter.Value></Setter>
            </Style>
            """);
        foreach (string name in new[] { "Translation", "Reading", "Shortcuts", "What you have picked up", "Local engines", "Contextual meanings", "Appearance", "Access" })
            navigation.Items.Add(new ListBoxItem { Style = itemStyle, Content = name == "What you have picked up" ? "Learning & Word Book" : name, Tag = name, Padding = new Thickness(12, 10, 8, 10), Margin = new Thickness(0, 2, 0, 2), FontFamily = Ui.Font, FontSize = 13, Foreground = Ui.Ink });
        rail.Children.Add(navigation); Children.Add(rail);
        var body = new DockPanel(); Grid.SetColumn(body, 1); Children.Add(body);
        title.Margin = new Thickness(24, 26, 20, 12); DockPanel.SetDock(title, Dock.Top); body.Children.Add(title);
        panel = new SettingsPanel(model) { Width = double.NaN, HorizontalAlignment = HorizontalAlignment.Stretch, Background = System.Windows.Media.Brushes.Transparent };
        body.Children.Add(panel);
        navigation.SelectionChanged += (_, _) =>
        {
            if (navigation.SelectedItem is not ListBoxItem selected) return;
            SelectedPage = (string)selected.Tag; title.Text = (string)selected.Content; panel.ShowSection(SelectedPage);
        };
        navigation.SelectedIndex = 0;
    }
}
