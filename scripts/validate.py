#!/usr/bin/env python3
"""Проверка согласованности конфигурации репозитория.

Ловит ошибки, которые иначе всплыли бы через час кросс-сборки под QEMU:
опечатку в id платформы, ссылку на несуществующий скрипт, забытый раннер.
Выполняется быстро и без Docker, поэтому стоит первым в CI.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
ERRORS: list[str] = []


def err(msg: str) -> None:
    ERRORS.append(msg)


def check_platforms() -> dict:
    data = yaml.safe_load((ROOT / "platforms.yaml").read_text())
    platforms = data["platforms"]
    seen = set()

    for p in platforms:
        pid = p["id"]
        if pid in seen:
            err(f"platforms.yaml: дублирующийся id {pid!r}")
        seen.add(pid)

        for field in ("dockerfile", "docker_platform", "ros_distro", "cuda_arch",
                      "build_methods", "runners"):
            if field not in p:
                err(f"{pid}: отсутствует обязательное поле {field!r}")

        if not (ROOT / p["dockerfile"]).exists():
            err(f"{pid}: нет файла {p['dockerfile']}")

        for method in p.get("build_methods", []):
            if method not in p.get("runners", {}):
                err(f"{pid}: для способа {method!r} не задан раннер")

        # Кросс-сборка имеет смысл только когда целевая архитектура отличается
        # от архитектуры раннера.
        if "cross" in p.get("build_methods", []) and p["docker_platform"] == "linux/amd64":
            err(f"{pid}: способ 'cross' для linux/amd64 бессмыслен")

    return {p["id"]: p for p in platforms}


def check_packages(platforms: dict) -> None:
    pkg_dir = ROOT / "packages"
    names = set()

    for path in sorted(pkg_dir.glob("*.yaml")):
        d = yaml.safe_load(path.read_text())

        for field in ("name", "platforms"):
            if field not in d:
                err(f"{path.name}: отсутствует обязательное поле {field!r}")
                return

        # Источник задаётся ровно одним способом: git-репозиторий либо путь
        # внутри src/ этого репозитория.
        has_repo = bool(d.get("repo"))
        has_local = bool(d.get("local_path"))
        if has_repo == has_local:
            err(f"{path.name}: задайте ровно одно из полей 'repo' и 'local_path'")
        if has_local and not (ROOT / "src" / d["local_path"]).is_dir():
            err(f"{path.name}: local_path={d['local_path']!r} — нет каталога src/{d['local_path']}")

        if d["name"] in names:
            err(f"{path.name}: дублирующееся имя пакета {d['name']!r}")
        names.add(d["name"])

        if path.stem != d["name"]:
            err(f"{path.name}: имя файла не совпадает с полем name={d['name']!r}")

        for pid in d["platforms"]:
            if pid not in platforms:
                err(f"{path.name}: неизвестная платформа {pid!r}")

        for field in ("vcs_file", "pre_build"):
            ref = d.get(field)
            if ref and not (pkg_dir / ref).exists():
                err(f"{path.name}: {field}={ref!r} — файла нет в packages/")

        if d.get("src_subdir") and d["src_subdir"].startswith("/"):
            err(f"{path.name}: src_subdir должен быть относительным путём")


def check_remote_refs() -> None:
    """Проверяет, что указанные repo/ref существуют на самом деле.

    Требует сети, поэтому включается флагом. Ловит опечатки вроде ветки
    `ros2` вместо `ROS2` — имена веток регистрозависимы, и такая ошибка
    иначе всплывает только на шаге клонирования, после сборки базы.
    """
    for path in sorted((ROOT / "packages").glob("*.yaml")):
        d = yaml.safe_load(path.read_text())
        repo = d.get("repo")
        if not repo:
            continue
        ref = d.get("ref", "main")
        try:
            res = subprocess.run(
                ["git", "ls-remote", "--heads", "--tags", repo, ref],
                capture_output=True, text=True, timeout=60,
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            err(f"{path.name}: не удалось опросить {repo}: {exc}")
            continue

        if res.returncode != 0:
            err(f"{path.name}: репозиторий недоступен: {repo}\n    {res.stderr.strip()}")
        elif not res.stdout.strip():
            err(f"{path.name}: в {repo} нет ветки или тега {ref!r}")
        else:
            print(f"  ok  {d['name']}: {repo} @ {ref}")


def check_scripts() -> None:
    for path in list((ROOT / "scripts").glob("*.sh")) + list((ROOT / "packages").glob("*.sh")):
        text = path.read_text()
        if not text.startswith("#!"):
            err(f"{path.relative_to(ROOT)}: нет shebang")
        # verify-cuda.sh сознательно не использует -e: он должен пройти все
        # проверки и сообщить итог, а не падать на первой неудачной.
        if "set -e" not in text and path.name != "verify-cuda.sh":
            err(f"{path.relative_to(ROOT)}: нет 'set -e'")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check-remotes",
        action="store_true",
        help="дополнительно проверить, что repo/ref пакетов существуют (нужна сеть)",
    )
    args = ap.parse_args()

    platforms = check_platforms()
    check_packages(platforms)
    check_scripts()
    if args.check_remotes:
        check_remote_refs()

    if ERRORS:
        print("Найдены ошибки конфигурации:\n")
        for e in ERRORS:
            print(f"  ✗ {e}")
        sys.exit(1)

    print("Конфигурация согласована.")


if __name__ == "__main__":
    main()
