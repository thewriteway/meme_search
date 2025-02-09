import os
from PIL import Image
from transformers import AutoModelForCausalLM, AutoTokenizer
from constants import available_models
import logging

# set logging level
logging.basicConfig(level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s")

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


class TestImageToText:
    def __init__(self):
        pass

    def download(self):
        return None

    def extract(self, image_path):
        return "this is a test"


# class for model / tokenizer
class MoondreamImageToText:
    def __init__(self, model_id, revision):
        self.model_id = model_id
        self.revision = revision
        self.model = None
        self.tokenizer = None
        self.downloaded = False

    def download(self):
        logging.info(f"INFO: downloading tokenizer for model {self.model_id}...")
        self.tokenizer = AutoTokenizer.from_pretrained(self.model_id, revision=self.revision)
        logging.info("INFO:... complete")

        logging.info(f"INFO: downloading model for model {self.model_id}...")
        self.model = AutoModelForCausalLM.from_pretrained(self.model_id, trust_remote_code=True, revision=self.revision)
        logging.info("INFO:... complete")
        self.downloaded = True

        return None

    def extract(self, image_path):
        # check if downloaded
        if self.downloaded is False:
            message = "INFO: model not downloaded, downloading..."
            logging.info(message)
            self.download()
            logging.info("INFO: model downloaded, starting image processing")

        # normalize image_path to working directory
        image_path = "/app" + image_path

        # create prompt
        logging.info("STARTING: image_to_text extraction of image --> %s", image_path)
        prompt = "Describe this image, including any text you see on the image."

        # load in image
        image = Image.open(image_path)
        logging.info("DONE: image loaded, starting generation --> %s", image_path)

        # process image
        enc_image = self.model.encode_image(image)
        logging.info("DONE: image encoding complete, starting generation --> %s", image_path)
        description = self.model.answer_question(enc_image, prompt, self.tokenizer)
        logging.info("DONE: image to text generation complete --> %s", image_path)

        # cleanup description
        description = description.strip().split(" ")[3:]
        description[0] = description[0].capitalize()
        description = " ".join(description)
        logging.info("DONE: image to text cleanup complete --> %s", image_path)

        return description

    def get_model(self):
        return self.model

    def get_tokenizer(self):
        return self.tokenizer


# function to route ImageToText model based on model_name - return instance of correct model class
def model_selector(model_name: str) -> object:
    try:
        # check if model_name is valid
        if model_name not in available_models:
            error_msg = f"ERROR: choose_model failed with error: model_name {model_name} not found in model_dict"
            logging.error(error_msg)
            raise ValueError(error_msg)

        # get model_id and revision
        if model_name == "test":
            current_model = TestImageToText()
            return current_model
        else:  # current default - model = "moondream2"
            # initialize model
            current_model = MoondreamImageToText(model_id="vikhyatk/moondream2", revision="2024-08-26")

            # turn down transformers verbose logs
            # import transformers
            # transformers.logging.set_verbosity_error()

            # initialize logging
            logging.basicConfig(level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s")
            return current_model
    except Exception as e:
        error_msg = f"ERROR: choose_model failed with error: {e}"
        logging.error(error_msg)
        raise e
