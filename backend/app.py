from flask import Flask, request, jsonify
from flask_cors import CORS
import openai
import os

app = Flask(__name__)
CORS(app)

# Set your OpenAI API key
openai.api_key = os.environ.get('OPENAI_API_KEY')

@app.route('/generate-quote', methods=['POST'])
def generate_quote():
    try:
        data = request.json
        mood = data.get('mood', 'motivational')
        
        prompt = f"Generate an inspiring and uplifting quote about {mood}. Make it original, powerful, and suitable for sharing on social media. Include the quote and a brief author attribution (can be fictional)."
        
        response = openai.ChatCompletion.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=150
        )
        
        quote = response.choices[0].message.content.strip()
        
        return jsonify({
            'quote': quote,
            'mood': mood,
            'status': 'success'
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
