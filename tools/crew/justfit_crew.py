"""Equipo multi-agente (CrewAI, proceso jerárquico) para el desarrollo de JustFit.

Uso (crewai>=1.0 no admite Python 3.14; con uv se usa 3.12 sin tocar el sistema):
    set ANTHROPIC_API_KEY=...            (o la clave del proveedor elegido)
    uv run --python 3.12 --with-requirements tools/crew/requirements.txt tools/crew/justfit_crew.py

Variables opcionales:
    JUSTFIT_CREW_LLM   modelo de los trabajadores  (def. anthropic/claude-sonnet-5)
    JUSTFIT_CREW_MANAGER_LLM  modelo del Director   (def. anthropic/claude-opus-5-5)
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from crewai import LLM, Agent, Crew, Process, Task
from crewai.tools import BaseTool
from pydantic import BaseModel, Field

PROJECT_ROOT = Path(__file__).resolve().parents[2]
EDITABLE_ROOTS = ("lib", "test")


def _resolve(rel_path: str) -> Path:
    """Resuelve una ruta relativa al proyecto impidiendo salir de él."""
    path = (PROJECT_ROOT / rel_path).resolve()
    if PROJECT_ROOT not in path.parents and path != PROJECT_ROOT:
        raise ValueError(f"Ruta fuera del proyecto: {rel_path}")
    return path


# --------------------------------------------------------------------------- #
# Herramientas
# --------------------------------------------------------------------------- #
class ReadFileInput(BaseModel):
    path: str = Field(..., description="Ruta relativa a la raíz del proyecto, p. ej. lib/main.dart")


class ReadFileTool(BaseTool):
    name: str = "leer_archivo"
    description: str = "Lee un archivo del proyecto Flutter y devuelve su contenido con números de línea."
    args_schema: type[BaseModel] = ReadFileInput

    def _run(self, path: str) -> str:
        try:
            lines = _resolve(path).read_text(encoding="utf-8").splitlines()
        except (OSError, ValueError) as e:
            return f"ERROR: {e}"
        return "\n".join(f"{i + 1:>5}\t{line}" for i, line in enumerate(lines))


class SearchInput(BaseModel):
    text: str = Field(..., description="Texto literal a buscar en lib/")


class SearchCodeTool(BaseTool):
    name: str = "buscar_en_codigo"
    description: str = "Busca un texto literal en los archivos .dart de lib/ y devuelve archivo:línea: contenido."
    args_schema: type[BaseModel] = SearchInput

    def _run(self, text: str) -> str:
        hits = []
        for file in sorted((PROJECT_ROOT / "lib").rglob("*.dart")):
            for i, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                if text in line:
                    hits.append(f"{file.relative_to(PROJECT_ROOT).as_posix()}:{i}: {line.strip()}")
        return "\n".join(hits[:100]) or "Sin coincidencias."


class ReplaceInput(BaseModel):
    path: str = Field(..., description="Ruta relativa (solo bajo lib/ o test/)")
    old: str = Field(..., description="Fragmento exacto a sustituir (debe aparecer una sola vez)")
    new: str = Field(..., description="Fragmento nuevo")


class ReplaceInFileTool(BaseTool):
    name: str = "reemplazar_en_archivo"
    description: str = (
        "Sustituye un fragmento exacto y único de un archivo bajo lib/ o test/. "
        "Úsalo para cambios mínimos; no reescribe archivos completos."
    )
    args_schema: type[BaseModel] = ReplaceInput

    def _run(self, path: str, old: str, new: str) -> str:
        try:
            target = _resolve(path)
        except ValueError as e:
            return f"ERROR: {e}"
        if target.relative_to(PROJECT_ROOT).parts[0] not in EDITABLE_ROOTS:
            return f"ERROR: solo se permite editar bajo {EDITABLE_ROOTS}."
        raw = target.read_bytes().decode("utf-8")
        crlf = "\r\n" in raw
        content = raw.replace("\r\n", "\n")
        old_n, new_n = old.replace("\r\n", "\n"), new.replace("\r\n", "\n")
        count = content.count(old_n)
        if count != 1:
            return f"ERROR: el fragmento aparece {count} veces; debe ser único."
        content = content.replace(old_n, new_n)
        if crlf:  # conserva los finales de línea del archivo
            content = content.replace("\n", "\r\n")
        target.write_bytes(content.encode("utf-8"))
        return f"OK: {path} actualizado."


class FlutterInput(BaseModel):
    command: str = Field(..., description="'analyze' o 'test'")


class FlutterCommandTool(BaseTool):
    name: str = "ejecutar_flutter"
    description: str = "Ejecuta 'flutter analyze' o 'flutter test' en el proyecto y devuelve código de salida y salida."
    args_schema: type[BaseModel] = FlutterInput

    def _run(self, command: str) -> str:
        if command not in ("analyze", "test"):
            return "ERROR: solo se admite 'analyze' o 'test'."
        flutter = shutil.which("flutter")
        if flutter is None:
            return "ERROR: no se encuentra 'flutter' en el PATH."
        try:
            proc = subprocess.run(
                [flutter, command],
                cwd=PROJECT_ROOT,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=900,
            )
        except subprocess.TimeoutExpired:
            return f"ERROR: 'flutter {command}' superó el tiempo límite."
        output = (proc.stdout + proc.stderr)[-8000:]
        return f"exit_code={proc.returncode}\n{output}"


# --------------------------------------------------------------------------- #
# Agentes
# --------------------------------------------------------------------------- #
def build_crew() -> Crew:
    worker_llm = LLM(model=os.getenv("JUSTFIT_CREW_LLM", "anthropic/claude-sonnet-5"))
    manager_llm = LLM(model=os.getenv("JUSTFIT_CREW_MANAGER_LLM", "anthropic/claude-opus-5-5"))

    director = Agent(
        role="Director de Desarrollo de JustFit",
        goal=(
            "Coordinar al equipo para que cada cambio en JustFit quede implementado, "
            "compile sin avisos y pase los tests."
        ),
        backstory=(
            "Lead técnico de una app Flutter de armario virtual. Divide el trabajo, "
            "delega en el especialista adecuado y no da una tarea por cerrada hasta "
            "que Calidad confirma 'flutter analyze' y 'flutter test' en verde."
        ),
        llm=manager_llm,
        allow_delegation=True,
        verbose=True,
    )

    ui_dev = Agent(
        role="Desarrollador UI/UX Flutter",
        goal="Implementar cambios visuales en widgets Flutter usando exclusivamente el ColorScheme del tema.",
        backstory=(
            "Especialista en Material 3 y en el sistema de diseño de JustFit "
            "(lib/theme/, ColorScheme definido en lib/main.dart). Hace cambios "
            "mínimos, respeta const, snake_case y los comentarios existentes, y "
            "nunca usa colores hardcodeados en pantallas."
        ),
        tools=[ReadFileTool(), SearchCodeTool(), ReplaceInFileTool()],
        llm=worker_llm,
        allow_delegation=False,
        verbose=True,
    )

    qa = Agent(
        role="Ingeniero de Calidad y Tests",
        goal="Verificar que el proyecto compila sin problemas de análisis y que todos los tests pasan.",
        backstory=(
            "Responsable de estabilidad. Ejecuta 'flutter analyze' y 'flutter test', "
            "lee los fallos y los reporta con archivo y línea exactos. No edita código."
        ),
        tools=[FlutterCommandTool(), ReadFileTool()],
        llm=worker_llm,
        allow_delegation=False,
        verbose=True,
    )

    # En modo jerárquico las tareas no llevan agente: el Director las delega.
    fix_button = Task(
        description=(
            "Corrige el color del botón 'Eliminar prenda' de "
            "lib/screens/garment_detail_screen.dart (FilledButton.tonalIcon). "
            "Debe usar el tema actual: backgroundColor = scheme.errorContainer y "
            "foregroundColor = scheme.error, sin alphas ni colores hardcodeados. "
            "Comprueba en lib/main.dart que ambos ColorScheme (claro y oscuro) "
            "definen errorContainer/onErrorContainer; si no, añádelos con los "
            "valores Material 3 (claro: 0xFFF9DEDC/0xFF410E0B, oscuro: "
            "0xFF8C1D18/0xFFF9DEDC) para que errorContainer no herede 'error'."
        ),
        expected_output="Lista de archivos modificados y el fragmento final del estilo del botón.",
    )

    verify = Task(
        description=(
            "Ejecuta 'flutter analyze' y 'flutter test'. Si algo falla por el cambio "
            "anterior, pide la corrección al Desarrollador UI/UX y vuelve a verificar."
        ),
        expected_output="Resultado de analyze y test (exit codes y resumen) y veredicto final OK/FALLO.",
        context=[fix_button],
    )

    return Crew(
        agents=[ui_dev, qa],
        tasks=[fix_button, verify],
        process=Process.hierarchical,
        manager_agent=director,
        verbose=True,
    )


if __name__ == "__main__":
    result = build_crew().kickoff()
    print("\n=== RESULTADO ===\n", result)
