from fastapi import FastAPI
import logging
from image_to_text_generator.constants import APP_URL, APP_PORT

# initialize logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# initialize FastAPI app
app = FastAPI()

@app.get("/")
def home():
    logging.info("HELLO WORLD")
    return {"status": "HELLO WORLD"}

@app.post("/description_receiver")
def description_receiver(data: dict):
    logging.info(f"DESCRIPTION RECEIVER: {data}")
    return {"status": "DESCRIPTION RECEIVER"}

@app.post("/status_receiver")
def status_receiver(data: dict):
    logging.info(f"STATUS RECEIVER: {data}")
    return {"status": "STATUS RECEIVER"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="