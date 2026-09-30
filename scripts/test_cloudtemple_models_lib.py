import json
import os
import tempfile
import unittest

from cloudtemple_models_lib import load_models, render_models_nix


class RenderModelsNixTests(unittest.TestCase):
    def test_empty_list_renders_empty_attrset(self):
        self.assertEqual(render_models_nix([]), "{\n  models = {\n  };\n}\n")

    def test_renders_sorted_by_id(self):
        models = [{"id": "b-model"}, {"id": "a-model"}]
        out = render_models_nix(models)
        self.assertLess(out.index('"a-model"'), out.index('"b-model"'))

    def test_renders_name_equal_to_id(self):
        out = render_models_nix([{"id": "qwen3.6:27b"}])
        self.assertIn('"qwen3.6:27b" = {', out)
        self.assertIn('name = "qwen3.6:27b";', out)

    def test_escapes_quotes_in_id(self):
        out = render_models_nix([{"id": 'weird"id'}])
        self.assertIn('weird\\"id', out)


class LoadModelsTests(unittest.TestCase):
    def test_missing_file_raises_clear_error(self):
        with self.assertRaises(FileNotFoundError) as ctx:
            load_models("/nonexistent/path.json")
        self.assertIn("--fetch", str(ctx.exception))

    def test_loads_data_array(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "models.json")
            with open(path, "w") as f:
                json.dump({"data": [{"id": "x"}]}, f)
            self.assertEqual(load_models(path), [{"id": "x"}])


if __name__ == "__main__":
    unittest.main()
