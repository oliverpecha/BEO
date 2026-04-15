"""
BEO Preflight — BLU-09
Language detection + keyword short-circuit + nano-classifier fallback.
"""
import json, re, os, logging
from lingua import Language, LanguageDetectorBuilder

logger = logging.getLogger("beo.preflight")

_KW_PATH = os.environ.get("BEO_KEYWORDS_PATH", "/app/keywords.json")

with open(_KW_PATH, "r", encoding="utf-8") as f:
    _KW = json.load(f)

_SUPPORTED = _KW["supported_languages"]
_LINGUA_MAP = {
    "en": Language.ENGLISH,
    "es": Language.SPANISH,
    "ca": Language.CATALAN,
    "pt": Language.PORTUGUESE,
}

_DETECTOR = LanguageDetectorBuilder.from_languages(
    *[_LINGUA_MAP[l] for l in _SUPPORTED if l in _LINGUA_MAP]
).build()

_DESK_PATTERNS: dict[str, re.Pattern] = {
    lang: re.compile(
        r'\b(' + '|'.join(re.escape(t) for t in terms) + r')\b',
        re.IGNORECASE
    )
    for lang, terms in _KW["desk_triggers"].items()
}

_DESK_PATTERN_REGEX = re.compile(
    r'\b(is .+? down|is .+? open|is .+? available|is .+? running)\b',
    re.IGNORECASE
)

SLASH_REGISTRY = {"/opus": 5}

TIER_ALIASES = {
    1: "tier-1-brain",
    2: "tier-2-desk",
    3: "tier-3-field",
    4: "tier-4-extraction",
    5: "tier-5-vip",
}


def detect_language(text: str) -> str:
    lang = _DETECTOR.detect_language_of(text)
    return lang.iso_code_639_1.name.lower() if lang else "unknown"


def desk_keyword_match(text: str, lang: str) -> bool:
    if _DESK_PATTERN_REGEX.search(text):
        return True
    if lang == "unknown" or lang not in _DESK_PATTERNS:
        return False
    return bool(_DESK_PATTERNS[lang].search(text))


def preflight(text: str, attachments: int = 0, urls: list = None) -> tuple[int, bool]:
    urls = urls or []
    url_count  = len(urls)
    char_count = len(text)

    # Step 1a: Slash commands
    tier = next((v for k, v in SLASH_REGISTRY.items() if text.startswith(k)), None)
    if tier:
        logger.debug(f"[preflight] slash → tier {tier}")
        return tier, False

    # Step 1b + 1c: Extraction triggers
    if (url_count > 5
            or (url_count >= 1 and attachments >= 1)
            or (url_count >= 3 and char_count > 5_000)
            or attachments >= 1
            or char_count > 15_000):
        logger.debug(f"[preflight] extraction → tier 4")
        return 4, False

    # Step 1c: Field — has URLs but below extraction threshold
    if 1 <= url_count <= 5:
        logger.debug(f"[preflight] field (urls={url_count}) → tier 3")
        return 3, False

    # Step 1d: Desk keywords
    lang = detect_language(text)
    if desk_keyword_match(text, lang):
        logger.debug(f"[preflight] desk keyword (lang={lang}) → tier 2")
        return 2, True

    # Step 3: Nano-classifier fallback
    logger.debug(f"[preflight] → nano classifier")
    return None, None   # proxy.py calls nano when (None, None)
