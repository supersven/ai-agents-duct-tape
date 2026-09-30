import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "fetch_cloudtemple_models", os.path.join(_HERE, "fetch-cloudtemple-models.py")
)
fetch_cloudtemple_models = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fetch_cloudtemple_models)


class MainDispatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.prev_cwd = os.getcwd()
        os.chdir(self.tmp.name)
        open("flake.nix", "w").close()
        os.makedirs("data", exist_ok=True)
        with open("data/cloudtemple-models.json", "w") as f:
            json.dump({"data": [{"id": "a"}, {"id": "b"}]}, f)

    def tearDown(self):
        os.chdir(self.prev_cwd)

    def test_no_flags_prints_status_and_calls_nothing(self):
        calls = []
        buf = io.StringIO()
        with redirect_stdout(buf):
            fetch_cloudtemple_models.main(
                [],
                fetch_fn=lambda *a: calls.append("fetch"),
                update_fn=lambda *a: calls.append("update"),
            )
        self.assertEqual(calls, [])
        self.assertIn("2 cached models", buf.getvalue())

    def test_fetch_only_calls_fetch_not_update(self):
        calls = []
        fetch_cloudtemple_models.main(
            ["--fetch"],
            fetch_fn=lambda *a: calls.append("fetch"),
            update_fn=lambda *a: calls.append("update"),
        )
        self.assertEqual(calls, ["fetch"])

    def test_update_only_calls_update_not_fetch(self):
        calls = []
        fetch_cloudtemple_models.main(
            ["--update"],
            fetch_fn=lambda *a: calls.append("fetch"),
            update_fn=lambda *a: calls.append("update"),
        )
        self.assertEqual(calls, ["update"])

    def test_fetch_and_update_calls_both_in_order(self):
        calls = []
        fetch_cloudtemple_models.main(
            ["--fetch", "--update"],
            fetch_fn=lambda *a: calls.append("fetch"),
            update_fn=lambda *a: calls.append("update"),
        )
        self.assertEqual(calls, ["fetch", "update"])

    def test_missing_flake_nix_errors(self):
        os.remove("flake.nix")
        with self.assertRaises(SystemExit):
            fetch_cloudtemple_models.main([])


class DoFetchTests(unittest.TestCase):
    def test_missing_token_raises_clear_error(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SystemExit) as ctx:
                fetch_cloudtemple_models.do_fetch("/tmp/unused.json")
        self.assertIn("CLOUD_TEMPLE_API_TOKEN", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
