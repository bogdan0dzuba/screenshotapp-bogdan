#!/usr/bin/env python3
"""Generate privacy-safe README demos without recording the user's desktop."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"
SIZE = (800, 450)
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def font(size: int, bold: bool = False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT, size)


def canvas():
    image = Image.new("RGB", SIZE, "#17202b")
    draw = ImageDraw.Draw(image)
    for y in range(SIZE[1]):
        tone = int(31 + y * 22 / SIZE[1])
        draw.line((0, y, SIZE[0], y), fill=(tone, tone + 8, tone + 17))
    return image, draw


def glass(draw, box, radius=28, fill="#ecf1f5", outline="#ffffff"):
    draw.rounded_rectangle(box, radius, fill=fill, outline=outline, width=2)


def save(frames, name, duration=110):
    path = ASSETS / name
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration, loop=0, disposal=2)


def hotkey_demo():
    frames = []
    for index in range(30):
        image, draw = canvas()
        glass(draw, (105, 58, 695, 392), 32)
        draw.text((150, 92), "Настройки", font=font(30, True), fill="#1c1c1e")
        draw.text((150, 150), "Горячая клавиша", font=font(21, True), fill="#33363a")
        labels = ["Control", "Option", "Shift", "Command"]
        enabled = [False, False, True, True]
        for row, (label, on) in enumerate(zip(labels, enabled)):
            y = 195 + row * 38
            draw.text((165, y), label, font=font(17), fill="#33363a")
            color = "#0a84ff" if on else "#b9bec4"
            draw.rounded_rectangle((325, y - 1, 377, y + 25), 13, fill=color)
            cx = 363 if on else 339
            draw.ellipse((cx - 10, y + 2, cx + 10, y + 22), fill="white")
        pulse = 235 + int(12 * abs(15 - index) / 15)
        draw.rounded_rectangle((428, 205, 635, 291), 20, fill=(pulse, pulse, pulse + 3))
        draw.text((462, 221), "Сейчас", font=font(16), fill="#64686d")
        draw.text((449, 250), "Shift + Command + A", font=font(15, True), fill="#101114")
        draw.rounded_rectangle((428, 310, 635, 351), 12, fill="#0a84ff")
        draw.text((454, 319), "Применить", font=font(17, True), fill="white")
        frames.append(image)
    save(frames, "hotkey-demo.gif")


def editor_demo():
    frames = []
    tools = ["A", "BOX", "T", "BLUR", "COPY"]
    for index in range(36):
        image, draw = canvas()
        glass(draw, (55, 35, 745, 415), 28, "#e9edf1")
        draw.text((88, 61), "Редактор снимка", font=font(20, True), fill="#202124")
        draw.rounded_rectangle((86, 104, 714, 337), 16, fill="#ffffff")
        draw.text((120, 129), "План запуска", font=font(24, True), fill="#18202a")
        draw.line((120, 172, 600, 172), fill="#d4d9df", width=3)
        draw.text((120, 194), "1. Проверить сборку", font=font(18), fill="#424850")
        draw.text((120, 229), "2. Сделать снимок", font=font(18), fill="#424850")
        draw.text((120, 264), "3. Перетащить PNG", font=font(18), fill="#424850")
        phase = min(index // 7, 4)
        if phase >= 0:
            draw.line((555, 245, 636, 185), fill="#ff3b30", width=7)
            draw.polygon([(636, 185), (612, 188), (628, 207)], fill="#ff3b30")
        if phase >= 1:
            draw.rounded_rectangle((105, 186, 350, 259), 10, outline="#ff9f0a", width=5)
        if phase >= 2:
            draw.text((466, 281), "готово", font=font(21, True), fill="#0a84ff")
        if phase >= 3:
            draw.rounded_rectangle((578, 116, 683, 161), 10, fill="#d7d9dc")
            for x in range(586, 676, 9):
                draw.rectangle((x, 121, x + 5, 156), fill="#8e9399")
        for i, label in enumerate(tools):
            x = 150 + i * 102
            selected = i == phase
            draw.rounded_rectangle((x, 355, x + 88, 397), 12, fill="#0a84ff" if selected else "#d8dde2")
            label_box = draw.textbbox((0, 0), label, font=font(13, True))
            label_width = label_box[2] - label_box[0]
            draw.text((x + (88 - label_width) / 2, 368), label, font=font(13, True), fill="white" if selected else "#30343a")
        frames.append(image)
    save(frames, "editor-demo.gif")


def scroll_capture_demo():
    frames = []
    for index in range(40):
        image, draw = canvas()
        draw.text((54, 34), "Прокручиваемый снимок", font=font(27, True), fill="white")
        phase = min(index // 10, 3)
        if phase < 3:
            glass(draw, (68, 88, 512, 405), 22, "#f4f5f7")
            offset = phase * 90
            for row in range(8):
                y = 112 + row * 47 - offset
                if 95 < y < 380:
                    draw.rounded_rectangle((94, y, 480, y + 32), 8, fill=(220 - row * 5, 230, 241))
                    draw.text((110, y + 7), f"Раздел {row + 1}", font=font(15, row == 0), fill="#26313d")
            draw.rounded_rectangle((548, 120, 735, 174), 14, fill="#0a84ff")
            draw.text((582, 136), "Прокрутите", font=font(17, True), fill="white")
            draw.line((641, 204, 641, 307), fill="#ffffff", width=5)
            draw.polygon([(641, 325), (626, 300), (656, 300)], fill="white")
        else:
            glass(draw, (210, 74, 590, 424), 20, "#f4f5f7")
            for row in range(8):
                y = 93 + row * 38
                draw.rounded_rectangle((235, y, 565, y + 27), 7, fill=(220 - row * 5, 230, 241))
                draw.text((248, y + 5), f"Раздел {row + 1}", font=font(13, row == 0), fill="#26313d")
            draw.rounded_rectangle((515, 29, 724, 67), 12, fill="#30d158")
            draw.text((544, 38), "Склеено в один PNG", font=font(15, True), fill="#102416")
        frames.append(image)
    save(frames, "scroll-capture-demo.gif")


if __name__ == "__main__":
    ASSETS.mkdir(parents=True, exist_ok=True)
    hotkey_demo()
    editor_demo()
    scroll_capture_demo()
    print("README GIFs generated")
