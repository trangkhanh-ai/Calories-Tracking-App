require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const PORT = process.env.PORT || 3000;

app.post('/api/analyze-food', async (req, res) => {
  try {
    const { imageBase64 } = req.body;
    
    if (!imageBase64) {
      return res.status(400).json({ error: 'imageBase64 is required' });
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      return res.status(500).json({ error: 'Server misconfiguration: API key missing' });
    }

    // Compress image using sharp to prevent timeout
    const sharp = require('sharp');
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    const compressedBuffer = await sharp(imageBuffer)
      .resize(800)
      .jpeg({ quality: 70 })
      .toBuffer();
    const compressedBase64 = compressedBuffer.toString('base64');

    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text: "Bạn là chuyên gia dinh dưỡng người Việt Nam. Hãy phân tích ảnh thức ăn và trả về JSON.\nƯu tiên nhận diện các món ăn Việt Nam (phở, bún, cơm, bánh mì, v.v.).\n\nTrả về CHÍNH XÁC format JSON sau (không thêm markdown, không thêm text):\n{\n  \"food_detected\": true,\n  \"items\": [\n    {\n      \"name\": \"Tên món bằng tiếng Việt\",\n      \"name_en\": \"English name\",\n      \"serving_size\": \"Khẩu phần ước tính (VD: 1 bát / 300g)\",\n      \"calories\": 350,\n      \"protein_g\": 15.5,\n      \"carbs_g\": 45.0,\n      \"fat_g\": 8.2,\n      \"confidence\": 0.92\n    }\n  ],\n  \"image_quality\": \"good\",\n  \"notes\": \"Ghi chú bổ sung nếu có\"\n}\n\nQuy tắc:\n- Nếu không thấy thức ăn: food_detected = false, items = []\n- image_quality: \"good\" | \"low_light\" | \"blurry\" | \"too_far\"\n- confidence: 0.0 đến 1.0\n- Nếu có nhiều món: liệt kê tất cả trong mảng items\n- calories và macros là ước tính cho 1 khẩu phần thông thường"
              },
              {
                inlineData: {
                  mimeType: "image/jpeg",
                  data: compressedBase64
                }
              }
            ]
          }
        ],
        generationConfig: {
          temperature: 0.4,
          responseMimeType: "application/json"
        }
      })
    });

    const data = await response.json();
    
    if (!response.ok) {
      throw new Error(data.error?.message || 'Failed to analyze image');
    }

    const textResult = data.candidates[0].content.parts[0].text;
    const jsonResult = JSON.parse(textResult);

    res.json(jsonResult);
  } catch (error) {
    console.error('Error analyzing image:', error);
    res.status(500).json({ error: 'Failed to analyze image' });
  }
});

app.listen(PORT, () => {
  console.log(`Gemini Proxy Server running on http://localhost:${PORT}`);
  console.log(`Make sure GEMINI_API_KEY is set in your environment variables.`);
});
