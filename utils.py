"""
utils.py
--------

Funcións auxiliares usadas polos scripts de automatización.  Aquí
defínense chamadas a CompreFace para recoñecemento facial,
recuperación de matrículas, control de notificacións repetidas e
envío de mensaxes ao usuario (por exemplo, por MQTT, Telegram ou
Home Assistant).  Este módulo pódese ampliar segundo as necesidades
da túa instalación.
"""

import json
import os
import time
import datetime
from typing import Optional

import requests

# Cargar a lista de matrículas coñecidas dende un ficheiro JSON.  Se o
# ficheiro non existe, a lista estará baleira.
PLATES_PATH = os.path.join(os.path.dirname(__file__), 'known_plates.json')
try:
    with open(PLATES_PATH, 'r', encoding='utf-8') as f:
        KNOWN_PLATES = json.load(f)
except FileNotFoundError:
    KNOWN_PLATES = {}

# Configuración de CompreFace dende variables de contorno
COMPRE_FACE_HOST = os.getenv('COMPRE_FACE_HOST', 'http://compreface:8000')
COMPRE_FACE_API_KEY = os.getenv('COMPRE_FACE_API_KEY', '')

# Tempo mínimo entre notificacións da mesma identidade (en segundos)
NOTIFICATION_COOLDOWN = 3600  # 1 hora


def check_face(snapshot_url: str) -> Optional[str]:
    """Consulta CompreFace para recoñecer unha cara a partir dunha imaxe.

    Args:
        snapshot_url: URL de descarga da snapshot (accesible para
        CompreFace).

    Returns:
        Nome da persoa recoñecida ou None se non se recoñece.
    """
    if not COMPRE_FACE_API_KEY:
        print("[WARN] API key de CompreFace non configurada")
        return None
    try:
        # Descargar a imaxe
        resp = requests.get(snapshot_url, timeout=10)
        resp.raise_for_status()
        # Preparar a petición a CompreFace
        files = {'file': ('snapshot.jpg', resp.content)}
        url = f"{COMPRE_FACE_HOST}/api/v1/recognition/recognize"
        headers = {'x-api-key': COMPRE_FACE_API_KEY}
        r = requests.post(url, files=files, headers=headers, timeout=10)
        r.raise_for_status()
        data = r.json()
        # A estrutura da resposta contén 'result' -> list de candidatos
        for face in data.get('result', []):
            subjects = face.get('subjects', [])
            if subjects:
                # Devolve o nome da primeira coincidencia
                return subjects[0].get('subject')
        return None
    except Exception as e:
        print(f"[ERROR] Fallo no recoñecemento facial: {e}")
        return None


def check_plate(snapshot_url: str) -> Optional[str]:
    """Recoñece a matrícula dunha imaxe e compróbaa contra KNOWN_PLATES.

    Esta función é un esqueleto que debe completarse cunha chamada
    real a un servizo de recoñecemento de matrículas (por exemplo,
    PlateRecognizer ou OpenALPR).  Para demostrar a funcionalidade,
    asume que a matrícula está incluída no nome do ficheiro.

    Args:
        snapshot_url: URL do snapshot.

    Returns:
        Matrícula detectada se coincide con KNOWN_PLATES; se non se
        recoñece, devolve None.
    """
    # Exemplo: extraer o texto da matrícula da URL simulando un recoñecemento
    # Realmente debería chamarse a unha API de recoñecemento aquí.
    try:
        plate_candidate = os.path.basename(snapshot_url).split('.')[0]
        # Comprobar se a matrícula é coñecida
        if plate_candidate in KNOWN_PLATES:
            return plate_candidate
        return None
    except Exception:
        return None


def should_notify(identifier: str, last_notified: dict) -> bool:
    """Determina se se debe enviar unha notificación para un identificador.

    Compróbase se pasou máis dunha hora (NOTIFICATION_COOLDOWN) desde a
    última notificación asociada ao identificador.  Se non existe, créase
    a entrada.

    Args:
        identifier: Nome da persoa, matrícula ou outro identificador único.
        last_notified: Diccionario global de últimos avisos.

    Returns:
        True se se debe notificar, False se aínda está no tempo de espera.
    """
    now = time.time()
    last_time = last_notified.get(identifier)
    if last_time is None or (now - last_time) >= NOTIFICATION_COOLDOWN:
        last_notified[identifier] = now
        return True
    return False


def notify_user(camera: str, tipo: str, identificador: str) -> None:
    """Envía unha notificación ao usuario.

    Este é un stub que debe adaptarse ao método de notificación que
    utilices (MQTT, Telegram, notificación de Home Assistant, correo,
    etc.).  Por agora imprime unha mensaxe por consola.
    """
    timestamp = datetime.datetime.now().isoformat(timespec='seconds')
    print(f"[NOTIFY] {timestamp}: {tipo} detectado na cámara '{camera}': {identificador}")