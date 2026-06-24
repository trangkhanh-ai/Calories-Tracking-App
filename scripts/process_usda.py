import os
import pandas as pd

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data", "usda")

FOOD_FILE = os.path.join(DATA_DIR, "food.csv")
FOOD_NUTRIENT_FILE = os.path.join(DATA_DIR, "food_nutrient.csv")
NUTRIENT_FILE = os.path.join(DATA_DIR, "nutrient.csv")

OUTPUT_FILE = os.path.join(DATA_DIR, "usda_calorie_dataset.csv")

print("Reading USDA files...")

food = pd.read_csv(FOOD_FILE)
food_nutrient = pd.read_csv(FOOD_NUTRIENT_FILE)
nutrient = pd.read_csv(NUTRIENT_FILE)

print("food:", food.shape)
print("food_nutrient:", food_nutrient.shape)
print("nutrient:", nutrient.shape)

# Merge food_nutrient with nutrient names
merged = food_nutrient.merge(
    nutrient,
    left_on="nutrient_id",
    right_on="id",
    how="left"
)

# Keep only nutrients useful for calorie tracking
wanted_nutrients = {
    "Energy": "kcal_100g",
    "Protein": "protein_100g",
    "Carbohydrate, by difference": "carbs_100g",
    "Total lipid (fat)": "fat_100g",
    "Sugars, total including NLEA": "sugar_100g",
    "Fiber, total dietary": "fiber_100g",
    "Sodium, Na": "sodium_mg_100g",
}

merged = merged[merged["name"].isin(wanted_nutrients.keys())].copy()

# Rename nutrient names to app-friendly column names
merged["nutrient_column"] = merged["name"].map(wanted_nutrients)

# Pivot nutrients into columns
nutrition = merged.pivot_table(
    index="fdc_id",
    columns="nutrient_column",
    values="amount",
    aggfunc="first"
).reset_index()

# Merge with food names
final = food.merge(nutrition, on="fdc_id", how="inner")

# Keep useful columns
final = final.rename(columns={
    "description": "name",
    "data_type": "source_type"
})

columns = [
    "fdc_id",
    "name",
    "source_type",
    "kcal_100g",
    "protein_100g",
    "carbs_100g",
    "fat_100g",
    "sugar_100g",
    "fiber_100g",
    "sodium_mg_100g",
]

final = final[[col for col in columns if col in final.columns]]

# Remove foods without calories
final = final.dropna(subset=["kcal_100g"])

# Clean names
final["name"] = final["name"].astype(str).str.strip()

# Optional: sort by name
final = final.sort_values("name")

final.to_csv(OUTPUT_FILE, index=False)

print("Saved:", OUTPUT_FILE)
print("Rows:", len(final))
print(final.head(20))