import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

from scripts import generate_caltrack_brand_assets as generator


class GeneratorPathValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = json.loads(generator.IOS_CATALOG.read_text(encoding="utf-8"))

    def test_current_catalog_filenames_are_accepted(self) -> None:
        outputs = generator.ios_catalog_outputs()

        self.assertTrue(outputs)
        self.assertTrue(
            all(
                path.startswith(generator.IOS_APP_ICON_DIRECTORY + "/")
                for path, _ in outputs
            )
        )

    def test_catalog_rejects_unapproved_or_unsafe_filenames(self) -> None:
        cases = {
            "path traversal": "../../outside.png",
            "unexpected PNG": "Unexpected-AppIcon.png",
            "non-PNG file": "Icon-App-20x20@2x.jpg",
        }

        for label, filename in cases.items():
            with (
                self.subTest(label=label),
                tempfile.TemporaryDirectory() as temporary,
            ):
                catalog = copy.deepcopy(self.catalog)
                catalog["images"][0]["filename"] = filename
                catalog_path = Path(temporary) / "Contents.json"
                catalog_path.write_text(json.dumps(catalog), encoding="utf-8")

                with mock.patch.object(generator, "IOS_CATALOG", catalog_path):
                    with self.assertRaises(ValueError):
                        generator.ios_catalog_outputs()

    def test_catalog_rejects_missing_approved_filename(self) -> None:
        missing = self.catalog["images"][0]["filename"]
        catalog = copy.deepcopy(self.catalog)
        catalog["images"] = [
            entry for entry in catalog["images"] if entry["filename"] != missing
        ]

        with tempfile.TemporaryDirectory() as temporary:
            catalog_path = Path(temporary) / "Contents.json"
            catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
            with mock.patch.object(generator, "IOS_CATALOG", catalog_path):
                with self.assertRaises(ValueError):
                    generator.ios_catalog_outputs()

    def test_save_rejects_non_allowlisted_target_before_writing(self) -> None:
        image = Image.new("RGBA", (1, 1))

        with mock.patch.object(Image.Image, "save") as save:
            with self.assertRaises(ValueError):
                generator.save_png(image, "../outside.png")
            save.assert_not_called()


if __name__ == "__main__":
    unittest.main()
