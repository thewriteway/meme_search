import os
from transformers import AutoModelForCausalLM, AutoTokenizer
import logging
logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s"
)

# define cache location
cache_dir = "/models"

# create cache directory if it doesn't exist
if not os.path.exists(cache_dir):
    os.makedirs(cache_dir)

# set hf cache env variable to cache directory
os.environ["HF_HOME"] = cache_dir
os.environ["TRANSFORMERS_CACHE"] = cache_dir

# set model and tokenizer
model = None
tokenizer = None


# class for model / tokenizer
class TextToImageModel:
    def __init__(self, model_id, revision):
        self.model_id = model_id
        self.revision = revision
        self.model = None
        self.tokenizer = None

    def download_model(self):
        logging.info(f"INFO: downloading tokenizer for model {self.model_id}...")
        self.tokenizer = AutoTokenizer.from_pretrained(
            self.model_id, revision=self.revision
        )
        logging.info("INFO:... complete")

        logging.info(f"INFO: downloading model for model {self.model_id}...")
        self.model = AutoModelForCausalLM.from_pretrained(
            self.model_id, trust_remote_code=True, revision=self.revision
        )
        logging.info("INFO:... complete")

        return None

    def get_model(self):
        return self.model

    def get_tokenizer(self):
        return self.tokenizer
