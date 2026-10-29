using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;

namespace Babelstaarnet.Windows;

// Keep native control semantics and automation; use the compact grouped form
// appearance instead of the legacy rectangular Windows control templates.
internal static class FormControls
{
    [ThreadStatic] private static Dictionary<string, Style>? styles;
    private static Style GetStyle(string kind, string body)
    {
        styles ??= [];
        if (!styles.TryGetValue(kind, out var style))
            styles[kind] = style = (Style)XamlReader.Parse("<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='" + kind + "'>" + body + "</Style>");
        return style;
    }
    internal static void AddScrollStyle(ResourceDictionary resources) => resources[typeof(System.Windows.Controls.Primitives.ScrollBar)] = GetStyle("ScrollBar", Scroll);
    internal static void Apply(Control control)
    {
        string kind = control.GetType().Name;
        string? body = kind switch { nameof(CheckBox) => Check, nameof(ComboBox) => Combo, nameof(Slider) => Slide, _ => null };
        if (body is null) return;
        WindowsTheme.Current.AddResources(control.Resources);
        control.Style = GetStyle(kind, body);
    }
    private const string Scroll = """
      <Setter Property="Width" Value="12"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
        <Grid Background="{TemplateBinding Background}">
          <Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True" Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}" Value="{TemplateBinding Value}" ViewportSize="{TemplateBinding ViewportSize}">
            <Track.DecreaseRepeatButton><RepeatButton x:Name="back" Command="ScrollBar.PageUpCommand" Focusable="False"><RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
            <Track.Thumb><Thumb x:Name="thumb" MinHeight="24" MinWidth="6" Margin="3,2" Focusable="False"><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="3" Background="{DynamicResource Babel.Muted}"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
            <Track.IncreaseRepeatButton><RepeatButton x:Name="forward" Command="ScrollBar.PageDownCommand" Focusable="False"><RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
          </Track>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="Orientation" Value="Horizontal"><Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="12"/><Setter TargetName="thumb" Property="MinHeight" Value="6"/><Setter TargetName="thumb" Property="MinWidth" Value="24"/><Setter TargetName="thumb" Property="Margin" Value="2,3"/><Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/><Setter TargetName="back" Property="Command" Value="{x:Static ScrollBar.PageLeftCommand}"/><Setter TargetName="forward" Property="Command" Value="{x:Static ScrollBar.PageRightCommand}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
      """;
    private const string Check = """
      <Setter Property="Foreground" Value="{DynamicResource Babel.Ink}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
        <Grid Background="Transparent"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <Border x:Name="box" Width="14" Height="14" CornerRadius="3" BorderBrush="{DynamicResource Babel.Stroke}" BorderThickness="1" Background="{DynamicResource Babel.Surface}" VerticalAlignment="Center">
            <Path x:Name="tick" Data="M2,6 L5,9 10,3" Stroke="{DynamicResource Babel.OnAccent}" StrokeThickness="1.7" Visibility="Collapsed" Margin="1"/>
          </Border>
          <ContentPresenter Grid.Column="1" Margin="8,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="box" Property="Background" Value="{DynamicResource Babel.Accent}"/><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Babel.Accent}"/><Setter TargetName="tick" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Babel.Accent}"/><Setter TargetName="box" Property="BorderThickness" Value="2"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
      """;
    private const string Combo = """
      <Setter Property="MinHeight" Value="34"/><Setter Property="Foreground" Value="{DynamicResource Babel.Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Babel.Stroke}"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="ItemContainerStyle"><Setter.Value><Style TargetType="ComboBoxItem">
        <Setter Property="Foreground" Value="{DynamicResource Babel.Ink}"/><Setter Property="Padding" Value="9,6"/>
        <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
          <Border x:Name="item" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
            <ContentPresenter TextElement.Foreground="{TemplateBinding Foreground}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="item" Property="Background" Value="{DynamicResource Babel.Hover}"/></Trigger>
            <Trigger Property="IsSelected" Value="True"><Setter TargetName="item" Property="Background" Value="{DynamicResource Babel.AccentSoft}"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="item" Property="BorderBrush" Value="{DynamicResource Babel.Accent}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value></Setter>
      </Style></Setter.Value></Setter>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
        <Grid>
          <ToggleButton BorderBrush="{TemplateBinding BorderBrush}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Focusable="False" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" ClickMode="Press">
            <ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
              <Border x:Name="shell" CornerRadius="6" Background="{DynamicResource Babel.Surface}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
                <Path Data="M0,0 L3,3 6,0" Stroke="{DynamicResource Babel.Muted}" StrokeThickness="1.3" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,9,0"/>
              </Border>
              <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="shell" Property="Background" Value="{DynamicResource Babel.Hover}"/></Trigger></ControlTemplate.Triggers>
            </ControlTemplate></ToggleButton.Template>
          </ToggleButton>
          <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" TextElement.Foreground="{TemplateBinding Foreground}" Margin="11,6,30,6" HorizontalAlignment="Left" VerticalAlignment="Center" IsHitTestVisible="False"/>
          <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False">
            <Border MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}" Background="{DynamicResource Babel.Surface}" BorderBrush="{DynamicResource Babel.Stroke}" BorderThickness="1" CornerRadius="6" Padding="3">
              <ScrollViewer CanContentScroll="True"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
            </Border>
          </Popup>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter Property="BorderBrush" Value="{DynamicResource Babel.Accent}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
      """;
    private const string Slide = """
      <Setter Property="MinHeight" Value="24"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Slider">
        <Grid Background="Transparent">
          <Track x:Name="PART_Track" Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}" Value="{TemplateBinding Value}">
            <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Focusable="False"><RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Height="4" Background="{DynamicResource Babel.Accent}" CornerRadius="2" VerticalAlignment="Center"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
            <Track.Thumb><Thumb Width="18" Height="18"><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="{DynamicResource Babel.Surface}" BorderBrush="{DynamicResource Babel.Stroke}" BorderThickness="1" CornerRadius="9"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
            <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Focusable="False"><RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Height="4" Background="{DynamicResource Babel.Stroke}" CornerRadius="2" VerticalAlignment="Center"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
          </Track>
        </Grid>
        <ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
      """;
}
