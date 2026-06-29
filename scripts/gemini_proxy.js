require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

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

    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text: "Analyze this image and return a JSON object with: foodDetected (bool), foodName (string), calories (number), protein (number), carbs (number), fat (number), imageQuality (string, either 'good', 'low_light', 'blurry', or 'too_far'). If no food is detected, set foodDetected to false and the rest to 0 or empty strings."
              },
              {
                inlineData: {
                  mimeType: "image/jpeg",
                  data: imageBase64
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
