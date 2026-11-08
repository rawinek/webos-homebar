.pragma library
// Homebar colour themes (Launcher settings → Theme). "default" is the
// original look, spelled out; every other theme is two colours: an accent for
// the focused tile, its ring and the glow, and a base for the tiles, pills and
// the shade under the rail. A light base gives light tiles with dark text; the
// shade stays dark (a near-black of the base), so the text over it stays light.
// The theme's name is the text "theme_<id>" in Strings.js.
var themes = [
    {id: "default"},
    {id: "lime", accent: "#B6FF2E", base: "#1F2329"},
    {id: "lagoon", accent: "#D6FFCB", base: "#042F32"},
    {id: "midnight", accent: "#D7FFE0", base: "#050505"},
    {id: "amber", accent: "#FFC21A", base: "#1E1B14"},
    {id: "terracotta", accent: "#E26F4A", base: "#FFFCF4"},
    {id: "cherry", accent: "#FF173D", base: "#F9DEDF"},
    {id: "cobalt", accent: "#1D61F3", base: "#F1F4F9"},
    {id: "indigo", accent: "#263BAA", base: "#FFF4D6"},
    // Pure black and white for OLED screens: black shade, tiles and menu,
    // white text, focus and warnings, no coloured glow, app icons in greys (mono).
    {id: "amoled", mono: true}
];
var ids = themes.map(function(t) { return t.id; });

var original = {
    scrim: "#060709",           // the shade under the name and the rail
    surface: "#b8141519",       // the clock bar
    surfaceEdge: "#14ffffff",
    divider: "#33ffffff",
    chip: "#26282e",            // tiles and pills: solid, so nothing shows through
    chipEdge: "#3b3e46",
    tile: "#15161a",            // behind an app icon
    gap: "#0a0b0d",             // between a focused tile and its ring
    handle: "#e60a0b0d",
    focus: "#f2f3f5",           // the focused tile or pill
    ring: "#ffffff",
    onFocus: "#0b0c0e",
    onFocus2: "#4a4f58",
    heading: "#ffffff",         // the big name and the clock
    headingShadow: "#59000000",
    text: "#d6d9de",            // over the shade: the line under the name, what is on screen
    hint: "#a3a8b2",            // over the shade: what the keys do
    keyLabel: "#e3e5e9",
    ink: "#f2f3f5",             // on tiles and pills from here on
    ink2: "#d6d9de",
    ink3: "#a3a8b2",
    label: "#e3e5e9",
    dim: "#80858f",             // an HDMI input with nothing plugged in
    dim2: "#5f646d",
    keyEdge: "#57ffffff",
    track: "#1affffff",
    version: "#5a5f69",
    neutral: "#6b7a8f",         // the glow for anything but an app
    warning: "#f0b070"
};

function rgb(hex) {
    return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
}
function hex(c) {
    return "#" + c.map(function(v) { var s = Math.round(v).toString(16); return s.length < 2 ? "0" + s : s; }).join("");
}
// a moved toward b by t (0..1).
function mix(a, b, t) {
    var x = rgb(a), y = rgb(b);
    return hex([0, 1, 2].map(function(i) { return x[i] + (y[i] - x[i]) * t; }));
}
// "#AARRGGBB", as QML reads it.
function alpha(color, a) {
    var s = Math.round(a * 255).toString(16);
    return "#" + (s.length < 2 ? "0" + s : s) + color.substr(1);
}
// Relative luminance (WCAG).
function luminance(color) {
    var c = rgb(color).map(function(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function find(id) {
    for (var i = 0; i < themes.length; i++) if (themes[i].id === id) return themes[i];
    return themes[0];
}

// AMOLED: black where the panel draws anything but text, white for the
// text and the focused tile, greys only to tell parts apart.
var amoled = {
    mono: true,
    scrim: "#000000",
    surface: "#000000",
    surfaceEdge: "#33ffffff",
    divider: "#33ffffff",
    chip: "#000000",
    chipEdge: "#4dffffff",
    tile: "#000000",
    gap: "#000000",
    handle: "#f2000000",
    focus: "#ffffff",
    ring: "#ffffff",
    onFocus: "#000000",
    onFocus2: "#595959",
    heading: "#ffffff",
    headingShadow: "#00000000",
    text: "#e6e6e6",
    hint: "#a6a6a6",
    keyLabel: "#f2f2f2",
    ink: "#ffffff",
    ink2: "#d9d9d9",
    ink3: "#a6a6a6",
    label: "#f2f2f2",
    dim: "#808080",
    dim2: "#5c5c5c",
    keyEdge: "#66ffffff",
    track: "#26ffffff",
    version: "#737373",
    neutral: "#000000",
    // Editing, the update dot, popups' frames and errors: white too, so
    // nothing on screen has a colour.
    warning: "#ffffff"
};

// Every colour the panel uses, for a theme id (unknown: the default).
function palette(id) {
    var t = find(id);
    if (t.mono) return amoled;
    if (!t.accent) return original;
    var A = t.accent, B = t.base;
    var light = luminance(B) > 0.4;
    // Tiles and pills: the base itself, text toward black on a light base.
    var to = light ? "#000000" : "#ffffff";
    // White text on the accent unless it is a light colour.
    var onFocus = luminance(A) > 0.3 ? mix(A, "#000000", 0.88) : "#ffffff";
    // A near-black base still needs tiles that stand out from the shade.
    var chip = light ? mix(B, "#000000", 0.04) : luminance(B) < 0.005 ? mix(B, "#ffffff", 0.1) : B;
    // The shade, the clock bar and the text over them: always dark, from the
    // base, or from a near-black of it when the base is light.
    var D = light ? mix(B, "#000000", 0.88) : B;
    var scrim = mix(D, "#000000", 0.7);
    return {
        scrim: scrim,
        surface: alpha(scrim, 0.72),
        surfaceEdge: alpha("#ffffff", 0.08),
        divider: alpha("#ffffff", 0.2),
        chip: chip,
        chipEdge: mix(chip, to, light ? 0.14 : 0.12),
        tile: mix(chip, "#000000", light ? 0.1 : 0.35),
        gap: scrim,
        handle: alpha(scrim, 0.9),
        focus: A,
        ring: A,
        onFocus: onFocus,
        onFocus2: alpha(onFocus, 0.7),
        heading: "#ffffff",
        headingShadow: "#59000000",
        text: mix(D, "#ffffff", 0.82),
        hint: mix(D, "#ffffff", 0.6),
        keyLabel: mix(D, "#ffffff", 0.87),
        ink: mix(B, to, light ? 0.88 : 0.93),
        ink2: mix(B, to, light ? 0.75 : 0.82),
        ink3: mix(B, to, light ? 0.55 : 0.6),
        label: mix(B, to, light ? 0.82 : 0.87),
        dim: mix(B, to, light ? 0.4 : 0.45),
        dim2: mix(B, to, light ? 0.32 : 0.3),
        keyEdge: alpha("#ffffff", 0.34),
        track: alpha("#ffffff", 0.1),
        version: mix(D, "#ffffff", 0.3),
        neutral: A,
        warning: "#f0b070"
    };
}
