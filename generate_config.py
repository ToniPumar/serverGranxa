#!/usr/bin/env python3
"""
Script para xerar a configuración final de Frigate.

Combina o ficheiro xeral ``general.yml`` coa configuración de
cada cámara situada en ``cameras/*.yml`` nun único ficheiro
``config.yml``.  Este ficheiro pode ser lido directamente por
Frigate ao arrincar.

Requisitos: instalación da biblioteca PyYAML.  O script
``setup-toni.sh`` instala automaticamente esta dependencia antes
de executar este script.
"""

import os
import glob
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML non está instalado. Instalao con pip install pyyaml\n")
    sys.exit(1)


def main():
    """Xera config.yml combinando general.yml e tódolos ficheiros de cámara.

    Para permitir o uso de ancoras YAML definidas en ``general.yml`` nas
    definicións das cámaras, este script non carga cada ficheiro de forma
    independente.  En vez diso, concatena ``general.yml`` e as
    definicións de cámaras nun único documento YAML.  As cámaras
    móntanse baixo a clave de primeiro nivel ``cameras`` e cada ficheiro
    móvese con sangría de dous espazos.  Posteriormente, ``yaml.safe_load``
    procesa o documento e garda o resultado final en ``config.yml``.
    """

    base_dir = os.path.dirname(os.path.abspath(__file__))
    config_dir = os.path.join(base_dir, '..', 'config')
    general_path = os.path.join(config_dir, 'general.yml')
    cameras_dir = os.path.join(config_dir, 'cameras')
    output_path = os.path.join(config_dir, 'config.yml')

    if not os.path.isfile(general_path):
        raise FileNotFoundError(f"Non se atopa {general_path}")

    # Ler o contido de general.yml
    with open(general_path, 'r', encoding='utf-8') as f:
        general_text = f.read().rstrip()

    # Comezar o documento combinado co contido de general.yml
    combined = general_text + "\n\n" + "cameras:\n"

    # Engadir cada ficheiro de cámara con sangría de 2 espazos
    cam_files = sorted(glob.glob(os.path.join(cameras_dir, '*.yml')))
    for cam_file in cam_files:
        with open(cam_file, 'r', encoding='utf-8') as cf:
            cam_text = cf.read().rstrip()
        # Engadimos duas espazos ó inicio de cada liña non baleira
        indented_lines = []
        for line in cam_text.splitlines():
            if line.strip():
                indented_lines.append('  ' + line)
            else:
                indented_lines.append(line)
        combined += "\n".join(indented_lines) + "\n"

    # Cargar o YAML combinado
    config = yaml.safe_load(combined) or {}

    # Gardar o ficheiro combinado
    with open(output_path, 'w', encoding='utf-8') as out:
        yaml.dump(config, out, sort_keys=False, allow_unicode=True)
    print(f"Configuración combinada gardada en {output_path}")


if __name__ == '__main__':
    main()