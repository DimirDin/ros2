#!/usr/bin/env python3
"""Собирает матрицу сборки из platforms.yaml и packages/*.yaml.

Именно этот скрипт делает требование «новый пакет с минимальными изменениями»
реальным: workflow не знает имён пакетов, он читает то, что выдаёт генератор.

Использование:
    generate-matrix.py bases   [--methods cross,native-arm] [--platforms id,...]
    generate-matrix.py packages [--methods ...] [--platforms ...] [--packages ...]

Печатает одну строку JSON — готовое значение для strategy.matrix.include.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("Нужен PyYAML: pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load_platforms() -> dict[str, dict]:
    data = yaml.safe_load((ROOT / "platforms.yaml").read_text())
    return {p["id"]: p for p in data["platforms"]}


def load_packages() -> list[dict]:
    pkgs = []
    for path in sorted((ROOT / "packages").glob("*.yaml")):
        pkgs.append(yaml.safe_load(path.read_text()))
    return pkgs


def csv(value: str | None) -> list[str] | None:
    """Разбирает список через запятую, отбрасывая пробелы и пустые элементы."""
    if not value:
        return None
    items = [v.strip() for v in value.split(",") if v.strip()]
    return items or None


def check_known(requested, known, what: str) -> None:
    """Опечатка в фильтре иначе проявилась бы как пустая матрица без причины."""
    if not requested:
        return
    unknown = [r for r in requested if r not in known]
    if unknown:
        sys.exit(
            f"Неизвестные значения фильтра {what}: {', '.join(unknown)}\n"
            f"Допустимые: {', '.join(sorted(known))}"
        )


def runner_for(platform: dict, method: str):
    """Раннер для способа сборки. Список меток означает self-hosted."""
    return platform["runners"][method]


def expand(values, platform: dict, pid: str) -> str:
    """Подставляет параметры платформы в аргументы манифеста.

    Позволяет манифесту задать флаг, значение которого зависит от платформы,
    например -DDISTRO_ROS={ros_distro}: humble для JetPack 6, jazzy для JP7.
    Иначе такой пакет пришлось бы описывать отдельным манифестом на платформу.
    """
    subs = {
        "ros_distro": platform["ros_distro"],
        "cuda_arch": platform["cuda_arch"],
        "platform": pid,
    }
    out = []
    for v in values or []:
        s = str(v)
        for key, val in subs.items():
            s = s.replace("{" + key + "}", val)
        out.append(s)
    return " ".join(out)


def is_publisher(platform: dict, method: str) -> bool:
    """Публикует ли эта комбинация образ под каноническим тегом.

    Один и тот же образ собирается несколькими способами (cross и native-arm
    дают побайтово разный, но функционально идентичный результат). Если бы
    публиковали все, они бы наперегонки перезаписывали один тег. Поэтому
    канонический тег пишет только первый способ из build_methods; остальные
    собираются и тестируются, но публикуются под суффиксом способа.
    """
    return method == platform["build_methods"][0]


def is_self_hosted(runner) -> bool:
    """Раннер задан списком меток — значит self-hosted.

    Такие строки по умолчанию исключаются: job с runs-on на незарегистрированный
    self-hosted раннер не пропускается, а бесконечно висит в очереди.
    """
    return isinstance(runner, list)


def build_bases(platforms, want_platforms, want_methods, include_self_hosted):
    rows = []
    for pid, p in platforms.items():
        if want_platforms and pid not in want_platforms:
            continue
        for method in p["build_methods"]:
            if want_methods and method not in want_methods:
                continue
            runner = runner_for(p, method)
            if is_self_hosted(runner) and not include_self_hosted:
                continue
            rows.append(
                {
                    "platform": pid,
                    "method": method,
                    "runs_on": runner,
                    "dockerfile": p["dockerfile"],
                    "docker_platform": p["docker_platform"],
                    "ros_distro": p["ros_distro"],
                    "cuda_arch": p["cuda_arch"],
                    # QEMU нужен только когда архитектура раннера не совпадает
                    # с целевой, то есть ровно для метода cross.
                    "publish": is_publisher(p, method),
                    "needs_qemu": method == "cross",
                    "qemu_cpu": p.get("qemu_cpu", "") if method == "cross" else "",
                    "name": f"{pid} / {method}",
                }
            )
    return rows


def build_packages(
    platforms, packages, want_platforms, want_methods, want_packages, include_self_hosted
):
    rows = []
    for pkg in packages:
        if want_packages and pkg["name"] not in want_packages:
            continue
        for pid in pkg["platforms"]:
            if want_platforms and pid not in want_platforms:
                continue
            if pid not in platforms:
                sys.exit(f"{pkg['name']}: неизвестная платформа {pid!r}")
            p = platforms[pid]
            for method in p["build_methods"]:
                if want_methods and method not in want_methods:
                    continue
                runner = runner_for(p, method)
                if is_self_hosted(runner) and not include_self_hosted:
                    continue
                rows.append(
                    {
                        "package": pkg["name"],
                        "platform": pid,
                        "method": method,
                        "runs_on": runner,
                        "docker_platform": p["docker_platform"],
                        "ros_distro": p["ros_distro"],
                        "cuda_arch": p["cuda_arch"],
                        # Ровно одно из двух непусто; какое — решает манифест.
                        "repo_url": pkg.get("repo", ""),
                        "repo_ref": pkg.get("ref", "main"),
                        "src_subdir": pkg.get("src_subdir", "."),
                        "local_path": pkg.get("local_path", ""),
                        "apt_deps": " ".join(pkg.get("apt_deps") or []),
                        "cmake_args": expand(pkg.get("cmake_args"), p, pid),
                        "vcs_file": pkg.get("vcs_file", ""),
                        "pre_build": pkg.get("pre_build", ""),
                        "rosdep_skip_keys": pkg.get("rosdep_skip_keys", ""),
                        "publish": is_publisher(p, method),
                        "needs_qemu": method == "cross",
                        "qemu_cpu": p.get("qemu_cpu", "") if method == "cross" else "",
                        "name": f"{pkg['name']} / {pid} / {method}",
                    }
                )
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["bases", "packages"])
    ap.add_argument("--platforms", help="фильтр по id платформ, через запятую")
    ap.add_argument("--methods", help="фильтр по способам сборки, через запятую")
    ap.add_argument("--packages", help="фильтр по именам пакетов, через запятую")
    ap.add_argument(
        "--include-self-hosted",
        action="store_true",
        help="включить строки для self-hosted раннеров (Jetson). Без флага они "
        "исключаются, иначе job зависнет в очереди при отсутствии раннера.",
    )
    args = ap.parse_args()

    platforms = load_platforms()
    want_platforms = csv(args.platforms)
    want_methods = csv(args.methods)

    check_known(want_platforms, set(platforms), "--platforms")
    check_known(
        want_methods,
        {m for p in platforms.values() for m in p["build_methods"]},
        "--methods",
    )

    if args.kind == "bases":
        rows = build_bases(
            platforms, want_platforms, want_methods, args.include_self_hosted
        )
    else:
        pkgs = load_packages()
        check_known(csv(args.packages), {p["name"] for p in pkgs}, "--packages")
        rows = build_packages(
            platforms,
            pkgs,
            want_platforms,
            want_methods,
            csv(args.packages),
            args.include_self_hosted,
        )

    if not rows:
        sys.exit(
            "Матрица пуста: заданные фильтры не дали ни одной комбинации.\n"
            "Проверьте, что платформа перечислена в поле 'platforms' манифеста "
            "пакета, а способ сборки — в 'build_methods' платформы."
        )

    print(json.dumps(rows, ensure_ascii=False))


if __name__ == "__main__":
    main()
