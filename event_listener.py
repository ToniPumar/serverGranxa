#!/usr/bin/env python3
"""
event_listener.py
------------------

Este script subscribe ao topic ``frigate/events`` do broker MQTT
e procesa as mensaxes de eventos xeradas por Frigate.  Para cada
evento detecta se a entidade (persoa, coche, etc.) require un
recoñecemento de cara ou matrícula e decide se se debe enviar unha
notificación.  A lóxica de negocio está centralizada en
``utils.py``.

Características:
  * Soa unha notificación por identificador cada hora para evitar
    alertas repetidas (cara coñecida/descoñecida, matrícula ou logo).
  * Utiliza CompreFace para recoñecer caras coñecidas.  A chave de
    API e a URL do servizo lévanse dende o ficheiro .env.
  * Compara matrículas detectadas co listado ``known_plates.json``.
  * Utiliza Paho MQTT como cliente para subscribirse a ``frigate/events``.

O script arranca no servizo ``frigate-listener`` definido en
docker-compose.  Se precisa probalo fóra de Docker, asegúrese de
instalar as dependencias con ``pip install paho-mqtt requests``.
"""

import json
import os
import time
import datetime

import paho.mqtt.client as mqtt

from utils import check_face, check_plate, should_notify, notify_user

# Diccionario global onde se almacenan as últimas notificacións por
# identificador.  O identificador pode ser o nome dunha persoa,
# unha matrícula ou un texto de logo.
LAST_NOTIFIED = {}

# Configuración dende variables de entorno
MQTT_HOST = os.getenv('MQTT_HOST', 'localhost')
MQTT_PORT = int(os.getenv('MQTT_PORT', '1883'))


def on_connect(client, userdata, flags, rc):
    """Callback que se executa cando a conexión co broker é exitosa."""
    if rc == 0:
        print("[MQTT] Conectado ao broker")
        client.subscribe("frigate/events")
    else:
        print(f"[MQTT] Fallo na conexión co broker (codigo {rc})")


def on_message(client, userdata, msg):
    """Procesa cada mensaxe do tópico frigate/events."""
    try:
        payload = json.loads(msg.payload)
    except Exception as e:
        print(f"[ERROR] Non se puido decodificar a mensaxe MQTT: {e}")
        return
    # Só se procesan eventos do tipo 'new'
    if payload.get('type') != 'new':
        return
    after = payload.get('after', {})
    if not after.get('has_snapshot'):
        return
    label = after.get('label')
    camera = after.get('camera')
    event_id = after.get('id')
    snapshot_path = after.get('snapshot', {}).get('path')  # ruta relativa dentro de /media/frigate
    # Construír URL do snapshot baseándose na ruta
    snapshot_url = None
    if snapshot_path:
        snapshot_url = f"http://frigate:5000{snapshot_path}"

    # Procesar persoas e caras
    if label == 'person':
        # Consultar CompreFace para recoñecer a cara
        person_name = None
        if snapshot_url:
            person_name = check_face(snapshot_url)
        identifier = person_name or f"descoñecido_{event_id}"
        if should_notify(identifier, LAST_NOTIFIED):
            notify_user(camera, 'persoa', identifier)
    # Procesar coches (matrículas)
    elif label == 'car':
        plate_text = None
        if snapshot_url:
            plate_text = check_plate(snapshot_url)
        if plate_text:
            identifier = plate_text
            if should_notify(identifier, LAST_NOTIFIED):
                notify_user(camera, 'matrícula', plate_text)


def main():
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(MQTT_HOST, MQTT_PORT, 60)
    client.loop_forever()


if __name__ == '__main__':
    main()