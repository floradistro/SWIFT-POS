-- Register Gemini Image Generation Tool in your MCP gateway

INSERT INTO ai_tool_registry (
    name,
    category,
    description,
    definition,
    edge_function,
    requires_store_id,
    is_read_only,
    is_active,
    tool_mode
) VALUES (
    'generate_image',
    'media',
    'Generate professional images using Google Gemini Imagen AI',
    '{
        "type": "function",
        "function": {
            "name": "generate_image",
            "description": "Generate high-quality photorealistic images using AI based on text prompts",
            "parameters": {
                "type": "object",
                "properties": {
                    "prompt": {
                        "type": "string",
                        "description": "Detailed description of the image to generate. Be specific about style, lighting, composition, and desired aesthetic."
                    },
                    "aspect_ratio": {
                        "type": "string",
                        "enum": ["1:1", "16:9", "9:16", "4:3", "3:4"],
                        "description": "Aspect ratio for the generated image",
                        "default": "16:9"
                    },
                    "sample_count": {
                        "type": "integer",
                        "description": "Number of images to generate (1-4)",
                        "minimum": 1,
                        "maximum": 4,
                        "default": 1
                    }
                },
                "required": ["prompt"]
            }
        }
    }'::jsonb,
    'gemini-image-generate',
    false,
    true,
    true,
    'creative'
) ON CONFLICT (name) DO UPDATE SET
    definition = EXCLUDED.definition,
    edge_function = EXCLUDED.edge_function,
    updated_at = NOW();

-- Now let's create a simple RPC function as a wrapper
CREATE OR REPLACE FUNCTION generate_image_ai(
    p_prompt TEXT,
    p_aspect_ratio TEXT DEFAULT '16:9',
    p_sample_count INTEGER DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
    v_api_key TEXT := 'AIzaSyBg-S9Tkp3OdwdXpK0kmgu8ObIIOJbRI_k';
BEGIN
    -- Call Vertex AI Imagen via HTTP
    SELECT net.http_post(
        url := 'https://us-central1-aiplatform.googleapis.com/v1/projects/quantix-analytics/locations/us-central1/publishers/google/models/imagegeneration@006:predict',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_api_key
        ),
        body := jsonb_build_object(
            'instances', jsonb_build_array(
                jsonb_build_object('prompt', p_prompt)
            ),
            'parameters', jsonb_build_object(
                'sampleCount', p_sample_count,
                'aspectRatio', p_aspect_ratio
            )
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;
