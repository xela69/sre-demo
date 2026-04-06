# setup: pip install openai 
# python3 -m venv path/to/venv
# source path/to/venv/bin/activate
# python3 -m pip install openai
from openai import OpenAI

client = OpenAI()

user_prompt = input("prompt: ")
tellme_prompt = "specify what info you want there with prompt"
response = client.responses.create(
	input=user_prompt,
	instructions=tellme_prompt
	model="gpt-4o"
)

print(response.output_text)