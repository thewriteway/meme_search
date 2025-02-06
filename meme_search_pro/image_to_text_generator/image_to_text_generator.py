from PIL import Image
import logging
from model_init import model, tokenizer

# turn down transformers verbose logs
# import transformers
# transformers.logging.set_verbosity_error()

# initialize logging
logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s"
)


def image_to_text(image_path: str) -> str:
    try:
        # normalize image_path to working directory
        image_path = "/app" + image_path

        # create prompt
        logging.info("STARTING: image_to_text extraction of image --> %s", image_path)
        prompt = "Describe this image, including any text you see on the image."

        # load in image
        image = Image.open(image_path)
        logging.info("DONE: image loaded, starting generation --> %s", image_path)

        # process image
        enc_image = model.encode_image(image)
        logging.info("DONE: image encoding complete, starting generation --> %s", image_path)
        description = model.answer_question(enc_image, prompt, tokenizer)
        logging.info("DONE: image to text generation complete --> %s", image_path)


        # cleanup description
        description = description.strip().split(" ")[3:]
        description[0] = description[0].capitalize()
        description = " ".join(description)
        return description
    except Exception as e:
        error_msg = "ERROR: image_to_text extraction of image --> %s", image_path + f" failed with error: {e}"
        logging.error(error_msg)
        raise e
