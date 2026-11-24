"""Collecte paginée des offres fournisseur."""
import asyncio
import json
import os
import time
from urllib.parse import urlencode

import aiohttp


CONCURRENCE_MAX = 3


async def lire_page(session, url):
    async with session.get(url) as reponse:
        reponse.raise_for_status()
        return await reponse.json()


def construire_url(base_url, page, scenario, run):
    params = urlencode({"page": page, "scenario": scenario, "run": run})
    return f"{base_url}/offers?{params}"


def verifier_page(donnees, numero, total_pages=None):
    if not isinstance(donnees, dict):
        raise ValueError(f"La réponse de la page {numero} n'est pas un objet JSON.")
    if donnees.get("page") != numero:
        raise ValueError(f"Page attendue {numero}, page reçue {donnees.get('page')!r}.")
    if not isinstance(donnees.get("items"), list):
        raise ValueError(f"La page {numero} ne contient pas de liste 'items'.")
    nombre = donnees.get("total_pages")
    if not isinstance(nombre, int) or isinstance(nombre, bool) or nombre < 1:
        raise ValueError(f"Nombre total de pages invalide sur la page {numero}.")
    if total_pages is not None and nombre != total_pages:
        raise ValueError(f"Le nombre total de pages a changé sur la page {numero}.")
    return nombre


async def collecter_sequentiellement(session, base_url, scenario, run):
    premiere = await lire_page(
        session, construire_url(base_url, 1, scenario, run)
    )
    total_pages = verifier_page(premiere, 1)
    pages = {1: premiere}
    for numero in range(2, total_pages + 1):
        page = await lire_page(
            session, construire_url(base_url, numero, scenario, run)
        )
        verifier_page(page, numero, total_pages)
        pages[numero] = page
    return pages


async def collecter_concurremment(session, base_url, scenario, run, concurrence):
    premiere = await lire_page(
        session, construire_url(base_url, 1, scenario, run)
    )
    total_pages = verifier_page(premiere, 1)
    limite = asyncio.Semaphore(concurrence)

    async def recuperer(numero):
        async with limite:
            page = await lire_page(
                session, construire_url(base_url, numero, scenario, run)
            )
        verifier_page(page, numero, total_pages)
        return numero, page

    autres_pages = await asyncio.gather(
        *(recuperer(numero) for numero in range(2, total_pages + 1))
    )
    pages = {1: premiere}
    pages.update(autres_pages)
    return pages


async def main():
    port = int(os.environ.get("NOVAMARKET_API_PORT", "18080"))
    base_url = f"http://127.0.0.1:{port}"
    scenario = "clean"
    timeout = aiohttp.ClientTimeout(total=10)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        debut = time.perf_counter()
        pages_sequentielles = await collecter_sequentiellement(
            session, base_url, scenario, f"seq-{time.time_ns()}"
        )
        duree_sequentielle = time.perf_counter() - debut

        debut = time.perf_counter()
        pages_concurrentes = await collecter_concurremment(
            session, base_url, scenario, f"async-{time.time_ns()}", CONCURRENCE_MAX
        )
        duree_concurrente = time.perf_counter() - debut

    if pages_sequentielles != pages_concurrentes:
        raise RuntimeError("Les collectes séquentielle et concurrente diffèrent.")

    print(json.dumps({
        "scenario": scenario,
        "concurrence_max": CONCURRENCE_MAX,
        "pages_recues": len(pages_concurrentes),
        "sequentiel_s": round(duree_sequentielle, 3),
        "concurrent_s": round(duree_concurrente, 3),
        "memes_donnees": True,
        "pages": pages_concurrentes,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
