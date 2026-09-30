import importlib.util
import json
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "cloudtemple_model_report", os.path.join(_HERE, "cloudtemple-model-report.py")
)
cloudtemple_model_report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cloudtemple_model_report)

build_report = cloudtemple_model_report.build_report
coding_score = cloudtemple_model_report.coding_score
do_fetch_modelgrep = cloudtemple_model_report.do_fetch_modelgrep

MG_FIXTURES = [
    {
        "id": "qwen/qwen-coder-next",
        "maker": "qwen",
        "hugging_face_id": "Qwen/Qwen3-Coder-Next",
        "open_weights": {"params_b": 79.7},
        "capabilities": {"tools": True},
        "performance": {"throughput_tps": 50},
        "benchmarks": {"artificial_analysis": {"coding": 60.0, "intelligence": 55.0}},
    },
    {
        "id": "qwen/qwen3.6-27b",
        "maker": "qwen",
        "hugging_face_id": "Qwen/Qwen3.6-27B",
        "open_weights": {"params_b": 27.8},
        "capabilities": {"tools": True},
        "performance": {"throughput_tps": 90},
        "benchmarks": {"artificial_analysis": {"coding": 40.0, "intelligence": 50.0}},
    },
]

CT_MODELS = [{"id": "qwen-coder-next:80b"}, {"id": "qwen3.6:27b"}, {"id": "bge-m3:567m"}]


class BuildReportTests(unittest.TestCase):
    def test_unmatched_includes_non_llm_models(self):
        report = build_report(CT_MODELS, MG_FIXTURES)
        self.assertIn("bge-m3:567m", report["unmatched"])

    def test_matches_carry_metrics(self):
        report = build_report(CT_MODELS, MG_FIXTURES)
        match = next(m for m in report["matches"] if m["cloud_temple_id"] == "qwen-coder-next:80b")
        self.assertEqual(match["performance"]["throughput_tps"], 50)

    def test_proposal_ranks_by_coding_score_descending(self):
        report = build_report(CT_MODELS, MG_FIXTURES, agent_slots=["build", "plan"])
        self.assertEqual(report["proposal"]["build"]["cloud_temple_id"], "qwen-coder-next:80b")
        self.assertEqual(report["proposal"]["plan"]["cloud_temple_id"], "qwen3.6:27b")

    def test_proposal_skips_models_without_tools(self):
        no_tools = [dict(MG_FIXTURES[0], capabilities={"tools": False})]
        report = build_report([CT_MODELS[0]], no_tools, agent_slots=["build"])
        self.assertEqual(report["proposal"], {})


class CodingScoreTests(unittest.TestCase):
    def test_falls_back_to_intelligence_when_coding_missing(self):
        mg = {"benchmarks": {"artificial_analysis": {"coding": None, "intelligence": 42.0}}}
        self.assertEqual(coding_score(mg), 42.0)


class FetchPaginationTests(unittest.TestCase):
    def test_follows_has_more_until_exhausted(self):
        pages = [
            {"data": [{"id": "a"}], "has_more": True, "next_offset": 1},
            {"data": [{"id": "b"}], "has_more": False, "next_offset": None},
        ]
        calls = []

        def fake_fetch_page(base_url, page_size, offset):
            calls.append(offset)
            return pages[len(calls) - 1]

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "modelgrep-models.json")
            do_fetch_modelgrep(path, fetch_page=fake_fetch_page)
            with open(path) as f:
                written = json.load(f)
        self.assertEqual([m["id"] for m in written["data"]], ["a", "b"])
        self.assertEqual(calls, [0, 1])


if __name__ == "__main__":
    unittest.main()
