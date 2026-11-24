"""Point de départ du groupe. Implémenter le journal et le bilan de collecte ici."""


"""Journal d'exécution et bilan de collecte (S3 · M3-M4)."""
from __future__ import annotations

import json
import logging
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path


def configurer_journal(fichier: Path) -> logging.Logger:
    """Logs horodatés vers la console et vers un fichier propre à l'essai."""
    fichier.parent.mkdir(parents=True, exist_ok=True)
    journal = logging.getLogger("collecteur")
    journal.handlers.clear()
    journal.setLevel(logging.INFO)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    for handler in (logging.StreamHandler(), logging.FileHandler(fichier, mode="w", encoding="utf-8")):
        handler.setFormatter(fmt)
        journal.addHandler(handler)
    return journal


@dataclass
class Bilan:
    run: str
    scenario: str
    mode: str
    concurrence: int
    statut: str = "en_cours"
    pages_attendues: int | None = None
    pages_recues: int = 0
    pages_en_echec: list = field(default_factory=list)
    requetes_http: int = 0
    reprises: int = 0
    incidents: Counter = field(default_factory=Counter)
    lignes_vues: int = 0
    acceptees: int = 0
    rejetees: int = 0
    motifs_rejet: Counter = field(default_factory=Counter)
    duree_s: float = 0.0
    publie: bool = False
    fichiers: dict = field(default_factory=dict)

    def controle(self) -> bool:
        """Complétude : toutes les pages reçues et lignes vues = acceptées + rejetées."""
        return (self.pages_attendues is not None
                and self.pages_recues == self.pages_attendues
                and not self.pages_en_echec
                and self.lignes_vues == self.acceptees + self.rejetees)

    def ecrire(self, chemin: Path) -> None:
        chemin.parent.mkdir(parents=True, exist_ok=True)
        donnees = {k: (dict(v) if isinstance(v, Counter) else v) for k, v in self.__dict__.items()}
        donnees["controle_completude"] = self.controle()
        chemin.write_text(json.dumps(donnees, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
