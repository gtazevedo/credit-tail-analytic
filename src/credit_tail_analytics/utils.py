"""
credit_tail_analytics.utils
============================
Utilidades compartilhadas por todos os módulos do pacote.
"""
import os
from pathlib import Path


def find_project_root(anchor_files: tuple = ('pyproject.toml', 'dados', 'README.md')) -> Path:
    """
    Sobe a árvore de diretórios a partir do __file__ do chamador até encontrar
    um dos arquivos/diretórios âncora que marcam a raiz do projeto.

    Usado internamente pelos módulos para localizar `dados/` independentemente
    de onde o pacote esteja instalado ou de onde o script for executado.

    Parâmetros
    ----------
    anchor_files : tuple
        Nomes de arquivos ou diretórios que existem na raiz do projeto.

    Retorna
    -------
    Path
        Caminho absoluto da raiz do projeto.

    Raises
    ------
    FileNotFoundError
        Se nenhum âncora for encontrado após subir toda a árvore.
    """
    # Começa no diretório deste próprio arquivo e sobe
    current = Path(__file__).resolve().parent
    while True:
        for anchor in anchor_files:
            if (current / anchor).exists():
                return current
        parent = current.parent
        if parent == current:
            raise FileNotFoundError(
                f"Raiz do projeto não encontrada. "
                f"Âncoras buscadas: {anchor_files}. "
                f"Garanta que o projeto tem um dos arquivos: {anchor_files}."
            )
        current = parent


def dados_dir() -> Path:
    """Retorna o caminho para o diretório `dados/` na raiz do projeto."""
    return find_project_root() / 'dados'


def graficos_dir(create: bool = True) -> Path:
    """
    Retorna o caminho para o diretório `graficos/` na raiz do projeto.
    Cria o diretório automaticamente se `create=True`.
    """
    p = find_project_root() / 'graficos'
    if create:
        p.mkdir(exist_ok=True)
    return p
