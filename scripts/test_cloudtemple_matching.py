import unittest

from cloudtemple_matching import (
    find_match,
    match_all,
    parse_org_and_family,
    parse_params_b,
    weights_match,
)

MG_FIXTURES = [
    {
        "id": "qwen/qwen3.8-27b",
        "maker": "qwen",
        "hugging_face_id": "Qwen/Qwen3.8-27B",
        "open_weights": {"params_b": 27.8},
    },
    {
        "id": "google/gemma-4-31b-it",
        "maker": "google",
        "hugging_face_id": "google/gemma-4-31B-it",
        "open_weights": {"params_b": 31.3},
    },
    {
        "id": "mistralai/ministral-3b-2512",
        "maker": "mistralai",
        "hugging_face_id": "mistralai/Ministral-3-3B-Instruct-2512",
        "open_weights": {"params_b": 3.8},
    },
]


class ParsingTests(unittest.TestCase):
    def test_parse_org_and_family_slash_form(self):
        org, family = parse_org_and_family("Qwen/Qwen3.8-27B-FP8")
        self.assertEqual(org, "qwen")
        self.assertEqual(family, "Qwen3.8-27B-FP8")

    def test_parse_org_and_family_bare_tag_resolves_maker(self):
        org, _ = parse_org_and_family("gemma4:31b")
        self.assertEqual(org, "google")

    def test_parse_org_and_family_unresolvable_family(self):
        org, _ = parse_org_and_family("mediphi-clinical:4b")
        self.assertIsNone(org)

    def test_parse_params_b_billions(self):
        self.assertEqual(parse_params_b("gemma4:31b"), 31.0)

    def test_parse_params_b_millions(self):
        self.assertEqual(parse_params_b("bge-m3:567m"), 0.567)

    def test_weights_match_small_model_absolute_tolerance(self):
        self.assertTrue(weights_match(3.0, 3.8))

    def test_weights_match_large_model_relative_tolerance(self):
        self.assertTrue(weights_match(120.0, 116.8))
        self.assertFalse(weights_match(120.0, 90.0))


class FindMatchTests(unittest.TestCase):
    def test_matches_slash_form_by_org_name_and_weight(self):
        mg = find_match({"id": "Qwen/Qwen3.8-27B-FP8"}, MG_FIXTURES)
        self.assertIsNotNone(mg)
        self.assertEqual(mg["id"], "qwen/qwen3.8-27b")

    def test_matches_bare_tag_via_family_lookup(self):
        mg = find_match({"id": "gemma4:31b"}, MG_FIXTURES)
        self.assertIsNotNone(mg)
        self.assertEqual(mg["id"], "google/gemma-4-31b-it")

    def test_matches_within_absolute_weight_tolerance(self):
        mg = find_match({"id": "Ministral-3-3B-Instruct-2512-Q8_0.gguf"}, MG_FIXTURES)
        self.assertIsNotNone(mg)
        self.assertEqual(mg["id"], "mistralai/ministral-3b-2512")

    def test_no_match_for_embedding_model(self):
        self.assertIsNone(find_match({"id": "bge-m3:567m"}, MG_FIXTURES))


class MatchAllTests(unittest.TestCase):
    def test_splits_matched_and_unmatched(self):
        ct_models = [{"id": "gemma4:31b"}, {"id": "bge-m3:567m"}]
        matches, unmatched = match_all(ct_models, MG_FIXTURES)
        self.assertEqual(len(matches), 1)
        self.assertEqual(len(unmatched), 1)
        self.assertEqual(unmatched[0]["id"], "bge-m3:567m")


if __name__ == "__main__":
    unittest.main()
