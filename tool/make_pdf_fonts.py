# Erzeugt feste Schriftschnitte für die Rechnungs-PDFs aus den variablen
# Google-Schriften (PDF-Programme zeigen variable Schriften nicht immer an).
# Aufruf: python3 tool/make_pdf_fonts.py <RobotoSlab-VF.ttf> <Arimo-VF.ttf>
# Arimo hat dieselben Buchstabenformen wie Liberation Sans, eine der Schriften,
# die für den QR-Zahlteil vorgesehen sind.
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'fonts', 'pdf')
os.makedirs(base, exist_ok=True)
slab, arimo = sys.argv[1], sys.argv[2]
for src, name, w in [
    (slab, 'RobotoSlab-Light', 300),
    (slab, 'RobotoSlab-Regular', 400),
    (slab, 'RobotoSlab-Bold', 700),
    (arimo, 'Arimo-Regular', 400),
    (arimo, 'Arimo-Bold', 700),
]:
    f = TTFont(src)
    instantiateVariableFont(f, {'wght': w}, inplace=True, updateFontNames=True)
    f.save(os.path.join(base, name + '.ttf'))
    print(name)
