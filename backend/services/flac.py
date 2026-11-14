import os
import subprocess
import shutil

def _find_native_flac():
    """Busca el encoder FLAC nativo del sistema (más eficiente que ffmpeg)."""
    return shutil.which("flac")

def _find_ffmpeg():
    """Busca ffmpeg: primero en el PATH del sistema, luego en imageio_ffmpeg."""
    system_ffmpeg = shutil.which("ffmpeg")
    if system_ffmpeg:
        return system_ffmpeg
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return None

def convert_to_flac(input_path: str, output_path: str, compression_level: int = 5) -> bool:
    """
    Convierte un archivo de audio a FLAC (lossless).
    
    Estrategia (según roadmap Fase 2):
    1. Preferir encoder nativo 'flac' con --verify (integridad garantizada)
    2. Fallback a ffmpeg si 'flac' no está instalado
    
    Nivel de compresión: 5 (balance óptimo velocidad/tamaño según roadmap)
    Retorna True si fue exitoso, False de lo contrario.
    """
    # Si el archivo ya es FLAC, solo copiarlo
    if input_path.lower().endswith('.flac'):
        try:
            if os.path.abspath(input_path) != os.path.abspath(output_path):
                shutil.copy2(input_path, output_path)
            return True
        except Exception as e:
            print(f"Error copiando FLAC existente {input_path}: {e}")
            return False

    # Intento 1: Encoder nativo 'flac' (más rápido, soporta --verify)
    native_flac = _find_native_flac()
    if native_flac and input_path.lower().endswith('.wav'):
        cmd = [
            native_flac,
            f"-{compression_level}",  # Nivel de compresión (0-8)
            "--verify",               # Verificar integridad en tiempo real
            "--force",                # Sobrescribir si existe
            "-o", output_path,        # Archivo de salida
            input_path                # Archivo de entrada
        ]
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
            if result.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
                print(f"  ✓ Convertido con flac nativo (nivel {compression_level}, verificado): {os.path.basename(input_path)}")
                return True
            else:
                print(f"  ⚠ flac nativo falló para {os.path.basename(input_path)}, intentando ffmpeg...")
        except subprocess.TimeoutExpired:
            print(f"  ⚠ flac nativo timeout para {os.path.basename(input_path)}, intentando ffmpeg...")
        except Exception as e:
            print(f"  ⚠ flac nativo excepción: {e}, intentando ffmpeg...")

    # Intento 2: FFmpeg como fallback (acepta cualquier formato de entrada)
    ffmpeg_exe = _find_ffmpeg()
    if not ffmpeg_exe:
        print(f"  ✗ No se encontró ni 'flac' ni 'ffmpeg'. No se puede convertir {os.path.basename(input_path)}")
        return False

    cmd = [
        ffmpeg_exe,
        "-y",                           # Sobrescribir sin preguntar
        "-i", input_path,               # Entrada
        "-c:a", "flac",                 # Codec FLAC
        "-compression_level", str(compression_level),  # Nivel 5
        output_path
    ]

    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
        if result.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            print(f"  ✓ Convertido con ffmpeg (nivel {compression_level}): {os.path.basename(input_path)}")
            return True
        else:
            print(f"  ✗ Error convirtiendo {os.path.basename(input_path)} a FLAC:\n{result.stderr[:500]}")
            return False
    except subprocess.TimeoutExpired:
        print(f"  ✗ Timeout al convertir {os.path.basename(input_path)} con ffmpeg (>5min)")
        return False
    except Exception as e:
        print(f"  ✗ Excepción al ejecutar ffmpeg para {os.path.basename(input_path)}: {e}")
        return False
