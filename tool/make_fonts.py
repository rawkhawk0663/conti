# Erzeugt feste Schriftschnitte aus den variablen Google-Schriften.
# Aufruf: python3 tool/make_fonts.py <Sora-VF.ttf> <PlexSans-VF.ttf>
# (Die variablen Dateien liegen nicht im Projekt, nur die festen Schnitte.)
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'fonts')
sora, plex = sys.argv[1], sys.argv[2]
for src, name, axes in [
    (sora, 'Sora-SemiBold', {'wght': 600}),
    (sora, 'Sora-Bold', {'wght': 700}),
    (plex, 'IBMPlexSans-Light', {'wght': 300, 'wdth': 100}),
    (plex, 'IBMPlexSans-Regular', {'wght': 400, 'wdth': 100}),
    (plex, 'IBMPlexSans-Medium', {'wght': 500, 'wdth': 100}),
    (plex, 'IBMPlexSans-SemiBold', {'wght': 600, 'wdth': 100}),
]:
    f = TTFont(src)
    instantiateVariableFont(f, axes, inplace=True, updateFontNames=True)
    f.save(os.path.join(base, name + '.ttf'))
    print(name)
