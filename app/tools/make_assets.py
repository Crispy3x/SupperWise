# Builds Supperwise/Assets.xcassets: paper colours (light + dark), accent, dish photos, app icon.
import json, os, shutil, sys
ROOT = os.path.join(os.path.dirname(__file__), "..")
A = os.path.join(ROOT, "Supperwise", "Assets.xcassets")
DESIGN = os.path.join(ROOT, "..", "design")
os.makedirs(A, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(A, "Contents.json"), "w"), indent=2)

def rgb(h):
    h = h.lstrip("#")
    return {"red": f"0x{h[0:2]}", "green": f"0x{h[2:4]}", "blue": f"0x{h[4:6]}", "alpha": "1.000"}

def colorset(name, light, dark):
    d = os.path.join(A, f"{name}.colorset"); os.makedirs(d, exist_ok=True)
    json.dump({"colors": [
        {"idiom": "universal", "color": {"color-space": "srgb", "components": rgb(light)}},
        {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
         "color": {"color-space": "srgb", "components": rgb(dark)}}],
        "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)

colorset("PaperGround", "FBF3EA", "1D1311")
colorset("PaperRaised", "FFFFFF", "2A1C19")
colorset("PaperInk", "2B1611", "F6E9DF")
colorset("PaperInk2", "6B5148", "C9B2A7")
colorset("PaperRule", "E7D8CC", "3B2A25")
colorset("PaperChip", "F3E5D8", "33231F")
colorset("AccentColor", "AD321C", "E2654B")

# Stand-in photos (Unsplash licence) — replace with the app's own recipe photography before launch.
photos = {
    "dish_tikka": "1588166524941-3bf61a9c41db", "dish_penne": "1621996346565-e3dbc646d9a9",
    "dish_shakshuka": "1590412200988-a436970781fa", "dish_meatballs": "1529042410759-befb1204b468",
    "dish_chicken": "1598103442097-8b74394b95c6", "dish_noodles": "1617093727343-374698b1b08d",
    "dish_salmon": "1467003909585-2f8a72700288", "dish_ragu": "1551183053-bf91a1d81141",
    "dish_drumsticks": "1626082927389-6cd097cdc6ec", "dish_dal": "1565557623262-b51c2513a641",
    "dish_curry": "1604908176997-125f25cc6f3d",
}
for name, pid in photos.items():
    src = os.path.join(DESIGN, "img", f"{pid}.jpg")
    d = os.path.join(A, f"{name}.imageset"); os.makedirs(d, exist_ok=True)
    shutil.copy(src, os.path.join(d, f"{name}.jpg"))
    json.dump({"images": [{"idiom": "universal", "filename": f"{name}.jpg"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)

# App icon: one 1024 px image (iOS 17+ single-size), rendered from the design's SVG.
d = os.path.join(A, "AppIcon.appiconset"); os.makedirs(d, exist_ok=True)
json.dump({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
print("assets written; render AppIcon.png next")
