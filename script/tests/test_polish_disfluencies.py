import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from polish_guard import clean_disfluencies, validate


class DisfluencyTests(unittest.TestCase):
    def test_reported_classroom_example(self):
        source = '今天呢，主要是那个在语文啊，语文的课程中呢，获得了什么呢？那个进步之星，进步之星的称号。'
        expected = '今天，主要是在语文课程中，获得了进步之星的称号。'
        self.assertEqual(clean_disfluencies(source), expected)
        output = '今天主要是在语文课程中获得了“进步之星”的称号。'
        result = validate(source, json.dumps({'text': output}), 'stop')
        self.assertEqual(result['text'], output)
        self.assertTrue(result['accepted'])
        for response, finish in [('invalid', 'stop'), ('', 'length')]:
            self.assertEqual(validate(source, response, finish)['text'], expected)
        # The actual old model dropped the locative preposition: retain the safe cleanup.
        result = validate(source, json.dumps({'text': '今天主要是语文课程中获得了进步之星的称号。'}), 'stop')
        self.assertEqual(result['text'], expected)

    def test_sentence_internal_restarts(self):
        for source, output in [
            ('我我觉得这个这个模型模型还需要优化。', '我觉得这个模型还需要优化。'),
            ('我们我们我们希望用户用户可以可以直接使用。', '我们希望用户可以直接使用。'),
            ('不要让让用户再去配置环境。', '不要让用户再去配置环境。'),
            ('需要配置配置环境。', '需要配置环境。'),
            ('在数学啊，数学课程中呢，有一些收获。', '在数学课程中，有一些收获。'),
        ]:
            with self.subTest(source=source):
                self.assertEqual(clean_disfluencies(source), output)
                self.assertEqual(validate(source, json.dumps({'text': output}), 'stop')['text'], output)
                self.assertEqual(validate(source, 'bad json', 'stop')['text'], output)

    def test_meaningful_reduplications_and_questions_survive(self):
        cases = [
            '大家慢慢看看，一件件检查，不要着急。', '我们研究研究，讨论讨论。',
            '一堆堆文件需要整理。', '不不，我不同意。', '好好学习，天天向上。',
            '人人都知道，渐渐会习惯。', '让让路，谢谢。', '张伟，张伟的同事来了。',
            '今天获得了什么呢？', '获得了什么呢？那个方案还没确定。',
            '那个方案可能不能通过，不要直接提交。', '就是那个在门口等我的人。',
            '他说“我我觉得这个这个”必须逐字保留。', '打印 `模型模型` 和 modelmodel。',
            '重复输入 1122，不是 12。', '不要啊，不要取消订单。',
        ]
        for source in cases:
            with self.subTest(source=source):
                self.assertEqual(clean_disfluencies(source), source)

    def test_cleanup_does_not_license_other_rewrites(self):
        cases = [
            ('我我可能不能参加。', '我能参加。', '我可能不能参加。'),
            ('模型模型费用是1122元。', '模型费用是12元。', '模型费用是1122元。'),
            ('我们我们请张伟联系李娜。', '我们请李娜联系张伟。', '我们请张伟联系李娜。'),
            ('他说“慢慢看看”。', '他说“慢看”。', '他说“慢慢看看”。'),
        ]
        for source, output, fallback in cases:
            with self.subTest(source=source):
                self.assertEqual(validate(source, json.dumps({'text': output}), 'stop')['text'], fallback)
