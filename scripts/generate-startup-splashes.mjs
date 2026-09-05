#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const GLASS_PADDING_PX = 16;
const GLASS_RADIUS_PX = 40;
const GLASS_EDGE_PX = 4;
const MASK_ALPHA_THRESHOLD = 128;
const GLASS_FILL = [235, 244, 250, 34];
const GLASS_EDGE = [205, 224, 237, 116];

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const value of buffer) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, 'ascii');
  const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length, 0);
  typeBuffer.copy(result, 4);
  data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), data.length + 8);
  return result;
}

function paeth(left, up, upperLeft) {
  const estimate = left + up - upperLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upperLeftDistance = Math.abs(estimate - upperLeft);
  if (leftDistance <= upDistance && leftDistance <= upperLeftDistance) {
    return left;
  }
  return upDistance <= upperLeftDistance ? up : upperLeft;
}

function decodeRgbaPng(buffer, filename) {
  if (!buffer.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    throw new Error(`${filename}: invalid PNG signature`);
  }

  let offset = PNG_SIGNATURE.length;
  let width = 0;
  let height = 0;
  const idat = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    offset += length + 12;
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      if (data[8] !== 8 || data[9] !== 6 || data[10] !== 0 || data[11] !== 0 || data[12] !== 0) {
        throw new Error(`${filename}: expected a non-interlaced 8-bit RGBA PNG`);
      }
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
  }

  if (width === 0 || height === 0 || idat.length === 0) {
    throw new Error(`${filename}: incomplete PNG`);
  }
  const packed = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * 4;
  if (packed.length !== height * (stride + 1)) {
    throw new Error(`${filename}: unexpected decompressed PNG size`);
  }

  const pixels = Buffer.alloc(width * height * 4);
  let packedOffset = 0;
  for (let y = 0; y < height; y++) {
    const filter = packed[packedOffset++];
    const rowOffset = y * stride;
    for (let x = 0; x < stride; x++) {
      const raw = packed[packedOffset++];
      const left = x >= 4 ? pixels[rowOffset + x - 4] : 0;
      const up = y > 0 ? pixels[rowOffset + x - stride] : 0;
      const upperLeft = y > 0 && x >= 4 ? pixels[rowOffset + x - stride - 4] : 0;
      let predictor = 0;
      if (filter === 1) {
        predictor = left;
      } else if (filter === 2) {
        predictor = up;
      } else if (filter === 3) {
        predictor = Math.floor((left + up) / 2);
      } else if (filter === 4) {
        predictor = paeth(left, up, upperLeft);
      } else if (filter !== 0) {
        throw new Error(`${filename}: unsupported PNG filter ${filter}`);
      }
      pixels[rowOffset + x] = (raw + predictor) & 0xff;
    }
  }
  return { width, height, pixels };
}

function encodeRgbaPng(width, height, pixels) {
  const stride = width * 4;
  const packed = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    const packedOffset = y * (stride + 1);
    packed[packedOffset] = 0;
    pixels.copy(packed, packedOffset + 1, y * stride, (y + 1) * stride);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    PNG_SIGNATURE,
    pngChunk('IHDR', header),
    pngChunk('IDAT', zlib.deflateSync(packed, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0))
  ]);
}

function squaredDistanceTransform1d(values, result, length, sites, boundaries) {
  let lastSite = 0;
  sites[0] = 0;
  boundaries[0] = -Infinity;
  boundaries[1] = Infinity;

  for (let position = 1; position < length; position++) {
    let boundary;
    do {
      const previous = sites[lastSite];
      boundary = ((values[position] + position * position) -
        (values[previous] + previous * previous)) / (2 * position - 2 * previous);
      if (boundary <= boundaries[lastSite]) {
        lastSite--;
      } else {
        break;
      }
    } while (lastSite >= 0);
    lastSite++;
    sites[lastSite] = position;
    boundaries[lastSite] = boundary;
    boundaries[lastSite + 1] = Infinity;
  }

  lastSite = 0;
  for (let position = 0; position < length; position++) {
    while (boundaries[lastSite + 1] < position) {
      lastSite++;
    }
    const delta = position - sites[lastSite];
    result[position] = delta * delta + values[sites[lastSite]];
  }
}

function squaredDistanceTransform(mask, width, height) {
  const infinity = 1e12;
  const temporary = new Float64Array(width * height);
  const distance = new Float64Array(width * height);
  const maxLength = Math.max(width, height);
  const values = new Float64Array(maxLength);
  const result = new Float64Array(maxLength);
  const sites = new Int32Array(maxLength);
  const boundaries = new Float64Array(maxLength + 1);

  for (let y = 0; y < height; y++) {
    const row = y * width;
    for (let x = 0; x < width; x++) {
      values[x] = mask[row + x] ? 0 : infinity;
    }
    squaredDistanceTransform1d(values, result, width, sites, boundaries);
    temporary.set(result.subarray(0, width), row);
  }
  for (let x = 0; x < width; x++) {
    for (let y = 0; y < height; y++) {
      values[y] = temporary[y * width + x];
    }
    squaredDistanceTransform1d(values, result, height, sites, boundaries);
    for (let y = 0; y < height; y++) {
      distance[y * width + x] = result[y];
    }
  }
  return distance;
}

function compositePixel(destination, destinationOffset, source, sourceOffset) {
  const sourceAlpha = source[sourceOffset + 3];
  if (sourceAlpha === 0) {
    return;
  }
  if (sourceAlpha === 255) {
    source.copy(destination, destinationOffset, sourceOffset, sourceOffset + 4);
    return;
  }
  const backgroundAlpha = destination[destinationOffset + 3];
  const visibleBackgroundAlpha = backgroundAlpha * (255 - sourceAlpha) / 255;
  const outputAlpha = sourceAlpha + visibleBackgroundAlpha;
  for (let channel = 0; channel < 3; channel++) {
    destination[destinationOffset + channel] = Math.round(
      (source[sourceOffset + channel] * sourceAlpha +
        destination[destinationOffset + channel] * visibleBackgroundAlpha) / outputAlpha);
  }
  destination[destinationOffset + 3] = Math.round(outputAlpha);
}

function makeGlassSplash(source) {
  const width = source.width + GLASS_PADDING_PX * 2;
  const height = source.height + GLASS_PADDING_PX * 2;
  const mask = new Uint8Array(width * height);
  for (let y = 0; y < source.height; y++) {
    for (let x = 0; x < source.width; x++) {
      const sourceOffset = (y * source.width + x) * 4;
      if (source.pixels[sourceOffset + 3] >= MASK_ALPHA_THRESHOLD) {
        mask[(y + GLASS_PADDING_PX) * width + x + GLASS_PADDING_PX] = 1;
      }
    }
  }

  const distance = squaredDistanceTransform(mask, width, height);
  const output = Buffer.alloc(width * height * 4);
  const radiusSquared = GLASS_RADIUS_PX * GLASS_RADIUS_PX;
  for (let pixel = 0; pixel < distance.length; pixel++) {
    if (distance[pixel] > radiusSquared) {
      continue;
    }
    const distanceFromShape = Math.sqrt(distance[pixel]);
    const edgeAmount = Math.max(0, Math.min(1,
      (distanceFromShape - (GLASS_RADIUS_PX - GLASS_EDGE_PX)) / GLASS_EDGE_PX));
    const coverage = Math.max(0, Math.min(1, GLASS_RADIUS_PX + 0.5 - distanceFromShape));
    const offset = pixel * 4;
    for (let channel = 0; channel < 3; channel++) {
      output[offset + channel] = Math.round(
        GLASS_FILL[channel] + (GLASS_EDGE[channel] - GLASS_FILL[channel]) * edgeAmount);
    }
    output[offset + 3] = Math.round(
      (GLASS_FILL[3] + (GLASS_EDGE[3] - GLASS_FILL[3]) * edgeAmount) * coverage);
  }

  for (let y = 0; y < source.height; y++) {
    for (let x = 0; x < source.width; x++) {
      const sourceOffset = (y * source.width + x) * 4;
      const destinationOffset = ((y + GLASS_PADDING_PX) * width + x + GLASS_PADDING_PX) * 4;
      compositePixel(output, destinationOffset, source.pixels, sourceOffset);
    }
  }
  return encodeRgbaPng(width, height, output);
}

function usage() {
  console.error('usage: generate-startup-splashes.mjs [--check] SOURCE_DIR TARGET_DIR');
  process.exit(2);
}

const args = process.argv.slice(2);
const checkOnly = args[0] === '--check';
if (checkOnly) {
  args.shift();
}
if (args.length !== 2) {
  usage();
}

const [sourceDirectory, targetDirectory] = args;
if (!checkOnly) {
  fs.mkdirSync(targetDirectory, { recursive: true });
}
let mismatch = false;
for (let index = 0; index < 13; index++) {
  const sourceFilename = path.join(sourceDirectory, `freecadsplash${index}_2x.png`);
  const targetFilename = path.join(targetDirectory, `freecadsplash${index}.png`);
  const source = decodeRgbaPng(fs.readFileSync(sourceFilename), sourceFilename);
  const generated = makeGlassSplash(source);
  if (checkOnly) {
    if (!fs.existsSync(targetFilename) || !fs.readFileSync(targetFilename).equals(generated)) {
      console.error(`outdated generated splash: ${targetFilename}`);
      mismatch = true;
    }
  } else if (!fs.existsSync(targetFilename) || !fs.readFileSync(targetFilename).equals(generated)) {
    fs.writeFileSync(targetFilename, generated);
    console.log(`generated ${targetFilename}`);
  }
}
if (mismatch) {
  process.exit(1);
}
