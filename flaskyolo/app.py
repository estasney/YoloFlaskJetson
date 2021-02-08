from typing import Tuple

from flask import Flask, request, jsonify, render_template, send_file
from yolov5.models.slim import SlimModelRunner
from PIL import Image, ImageDraw, ImageFont
import numpy as np
import base64
from io import BytesIO
import os
from datetime import timedelta
from logging.config import dictConfig
app = Flask(__name__)

dictConfig({
    'version':    1,
    'formatters': {
        'default': {
            'format': '[%(asctime)s] %(levelname)s in %(module)s: %(message)s',
            }
        },
    'handlers':   {
        'wsgi': {
            'class':     'logging.StreamHandler',
            'stream':    'ext://flask.logging.wsgi_errors_stream',
            'formatter': 'default'
            }
        },
    'root':       {
        'level':    'INFO',
        'handlers': ['wsgi']
        }
    })





app.config['SEND_FILE_MAX_AGE_DEFAULT'] = timedelta(seconds=0)
model = SlimModelRunner(weights=os.path.join(app.root_path, "model/model.pt"), device='cuda')
image_cache = {}


def draw_predict(img, pred, to_bytes=True):
    PAD = 4

    img = Image.fromarray(img.astype(np.uint8))
    fnt = ImageFont.truetype("DejaVuSans.ttf", 18)
    for detect in pred['detections']:
        box = detect['xyxy']
        cls = detect['cls']
        confidence = detect['confidence']
        d = ImageDraw.Draw(img)
        d.rectangle(box, width=PAD, outline='red')  # BBox
        cls_text = f"{cls} : {confidence.split('.')[0]}"
        cls_text_box_size = fnt.getbbox(cls_text)

        cls_xy = (box[0] + PAD, box[1] + cls_text_box_size[1] - PAD)

        # solid background for text
        d.rectangle((box[0], box[1] + cls_text_box_size[1], box[0] + cls_text_box_size[2] + PAD,
                     box[1] + cls_text_box_size[3] + PAD), fill='red')

        d.text(cls_xy, cls_text, font=fnt)

    if to_bytes:
        with BytesIO() as output:
            img.save(output, format="PNG")
            contents = output.getvalue()

        return contents
    else:
        return img


@app.route('/img/current', methods=['GET'])
def serve_image():
    if not image_cache:
        return jsonify({"message": "no cache"}), 404
    img_data = {k: v for k, v in image_cache.items()}  # copy
    drawings = []
    for k, data in img_data.items():
        img = data['img']
        pred = {k: v for k, v in data.items() if k != 'img'}
        drawings.append(draw_predict(img, pred, to_bytes=False))

    img_data.clear()
    del img_data

    width = drawings[0].size[0] * 2
    height = drawings[0].size[1] * 2

    stack_img = Image.new('RGB', (width, height))

    stack_img.paste(drawings[0])
    stack_img.paste(drawings[1], (width // 2, 0, width, height // 2))
    stack_img.paste(drawings[2], (0, height // 2, width // 2, height))
    stack_img.paste(drawings[3], (width // 2, height // 2, width, height))

    del drawings

    with BytesIO() as output:
        stack_img.save(output, format="PNG")
        contents = output.getvalue()

    del stack_img, output

    return send_file(BytesIO(contents), 'current.png')


@app.route('/current', methods=['GET'])
def imgdraw_current():
    return render_template("result.html")


@app.route('/current/<channel>', methods=['GET'])
def imgdraw_channel(channel):
    img_data = image_cache.get(channel)
    if not img_data:
        return jsonify({"message": "error"}), 404
    img = img_data['img']
    pred = {k: v for k, v in img_data.items() if k != 'img'}

    drawn = draw_predict(img, pred)
    img_b64 = base64.b64encode(drawn)
    img_b64 = img_b64.decode('utf-8')

    return render_template("result.html", img=img_b64)


@app.route('/')
def hello_world():
    return render_template("upload.html")


@app.route('/api', methods=['POST'])
def api_predict():
    img_tasks = []

    img_archive = request.data
    if not img_archive:
        return jsonify({'message': 'file not found'}), 404

    # noinspection PyTypeChecker
    img_archive = np.load(BytesIO(img_archive))

    for img_name, img_arr in img_archive.items():
        img_tasks.append((img_name, img_arr))

    predictions = model.detect([img for img_name, img in img_tasks])

    data_response = []

    for (img_name, img_arr), img_pred in zip(img_tasks, predictions):
        data_response.append({'img_id': img_name, **img_pred})
        image_cache[img_name] = {'img': img_arr.astype(np.uint8), **img_pred}

    return jsonify(data_response), 200


@app.route('/imgdraw', methods=['POST'])
def imgdraw():
    f = request.files['file']
    img = [np.array(Image.open(f))]
    pred = model.detect(img)[0]

    img_data = draw_predict(img[0], pred)
    img_b64 = base64.b64encode(img_data)
    img_b64 = img_b64.decode('utf-8')

    return render_template("result.html", img=img_b64)


if __name__ == '__main__':
    app.run()
