.pragma library
// Stable ids are saved per physical input, never inferred from a CEC name.
var catalog = [
    // The ports' own symbols: the default of USB drives and the analogue inputs.
    {
        "id": "usb",
        "title": "USB drive",
        "titleKey": "device_usb"
    },
    {
        "id": "av",
        "title": "AV"
    },
    {
        "id": "component",
        "title": "Component",
        "titleKey": "device_component"
    },
    {
        "id": "scart",
        "title": "SCART"
    },
    {
        "id": "amplifier",
        "title": "Amplifier",
        "titleKey": "device_amplifier"
    },
    {
        "id": "android-tv",
        "title": "Android TV"
    },
    {
        "id": "apple-tv",
        "title": "Apple TV"
    },
    {
        "id": "apple-tv-box",
        "title": "Apple TV (box)"
    },
    {
        "id": "asus",
        "title": "ASUS"
    },
    {
        "id": "receiver",
        "title": "AV receiver",
        "titleKey": "device_receiver"
    },
    {
        "id": "bluray",
        "title": "Blu-ray"
    },
    {
        "id": "bose",
        "title": "Bose"
    },
    {
        "id": "bose-soundtouch",
        "title": "Bose SoundTouch"
    },
    {
        "id": "cambridge-audio",
        "title": "Cambridge Audio"
    },
    {
        "id": "chromecast",
        "title": "Chromecast"
    },
    {
        "id": "denon",
        "title": "Denon"
    },
    {
        "id": "disc-player",
        "title": "Disc player",
        "titleKey": "device_disc_player"
    },
    {
        "id": "dune-hd",
        "title": "Dune HD"
    },
    {
        "id": "dvd",
        "title": "DVD"
    },
    {
        "id": "fire-tv",
        "title": "Fire TV"
    },
    {
        "id": "fire-tv-cube",
        "title": "Fire TV Cube"
    },
    {
        "id": "console",
        "title": "Game console",
        "titleKey": "device_console"
    },
    {
        "id": "google",
        "title": "Google"
    },
    {
        "id": "hdmi",
        "title": "HDMI"
    },
    {
        "id": "intel-nuc",
        "title": "Intel NUC"
    },
    {
        "id": "kodi",
        "title": "Kodi"
    },
    {
        "id": "laptop",
        "title": "Laptop"
    },
    {
        "id": "lg",
        "title": "LG"
    },
    {
        "id": "streamer",
        "title": "Media streamer",
        "titleKey": "device_streamer"
    },
    {
        "id": "monitor",
        "title": "Monitor",
        "titleKey": "device_monitor"
    },
    {
        "id": "gamecube",
        "title": "Nintendo GameCube"
    },
    {
        "id": "switch",
        "title": "Nintendo Switch"
    },
    {
        "id": "shield",
        "title": "NVIDIA Shield"
    },
    {
        "id": "onkyo",
        "title": "Onkyo"
    },
    {
        "id": "panasonic",
        "title": "Panasonic"
    },
    {
        "id": "pc",
        "title": "PC"
    },
    {
        "id": "playstation",
        "title": "PlayStation"
    },
    {
        "id": "ps3",
        "title": "PlayStation 3"
    },
    {
        "id": "ps4",
        "title": "PlayStation 4"
    },
    {
        "id": "ps5",
        "title": "PlayStation 5"
    },
    {
        "id": "projector",
        "title": "Projector",
        "titleKey": "device_projector"
    },
    {
        "id": "raspberry-pi",
        "title": "Raspberry Pi"
    },
    {
        "id": "roku",
        "title": "Roku"
    },
    {
        "id": "roku-ultra",
        "title": "Roku Ultra"
    },
    {
        "id": "samsung",
        "title": "Samsung"
    },
    {
        "id": "satellite",
        "title": "Satellite receiver",
        "titleKey": "device_satellite"
    },
    {
        "id": "saturn",
        "title": "Sega Saturn"
    },
    {
        "id": "set-top-box",
        "title": "Set-top box",
        "titleKey": "device_set_top_box"
    },
    {
        "id": "sonos",
        "title": "Sonos"
    },
    {
        "id": "sonos-arc",
        "title": "Sonos Arc"
    },
    {
        "id": "sonos-beam",
        "title": "Sonos Beam"
    },
    {
        "id": "sony",
        "title": "Sony"
    },
    {
        "id": "soundbar",
        "title": "Soundbar",
        "titleKey": "device_soundbar"
    },
    {
        "id": "speaker",
        "title": "Speaker",
        "titleKey": "device_speaker"
    },
    {
        "id": "speakers",
        "title": "Speakers",
        "titleKey": "device_speakers"
    },
    {
        "id": "steam",
        "title": "Steam"
    },
    {
        "id": "steam-deck",
        "title": "Steam Deck"
    },
    {
        "id": "wiim",
        "title": "WiiM"
    },
    {
        "id": "wiim-device",
        "title": "WiiM (device)"
    },
    {
        "id": "xbox",
        "title": "Xbox"
    },
    {
        "id": "xbox-console",
        "title": "Xbox (console)"
    },
    {
        "id": "xgimi",
        "title": "XGIMI Horizon"
    },
    {
        "id": "xiaomi",
        "title": "Xiaomi"
    },
    {
        "id": "yamaha",
        "title": "Yamaha AVR"
    },
    {
        "id": "zidoo",
        "title": "Zidoo"
    }
];
// TV has its own list: never offer consoles, streamers or audio logos here.
var tvCatalog = [
    {id: "tv", title: "TV"},
    {id: "tv-screen", titleKey: "tv_icon_screen"},
    {id: "tv-classic", titleKey: "tv_icon_classic"},
    {id: "tv-guide", titleKey: "tv_icon_guide"},
    {id: "tv-play", titleKey: "tv_icon_play"}
];
function index(id, list) {
    list = list || catalog;
    for (var i=0; i<list.length; i++) if (list[i].id === id) return i;
    return 0;
}
function icon(id) {
    for (var i=0; i<catalog.length; i++) if (catalog[i].id === id) return catalog[i];
    return catalog[index("hdmi")];
}
function tvIcon(id) { return tvCatalog[index(id, tvCatalog)]; }
function assignments(value) {
    var out = {};
    if (!value || typeof value !== "object" || Array.isArray(value)) return out;
    for (var key in value) {
        if (/^com\.webos\.app\.(hdmi|dp|usbc)\d$/.test(key) && typeof value[key] === "string" && icon(value[key]).id === value[key])
            out[key] = value[key];
    }
    return out;
}
