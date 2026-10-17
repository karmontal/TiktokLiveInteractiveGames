from livebridge.moderation import MAX_NAME_LEN, Moderator


def test_arabic_variants_are_caught():
    mod = Moderator(["كلب"])
    assert not mod.is_clean("يا كـــلب")
    assert not mod.is_clean("كَلْب")
    assert mod.is_clean("قلب")


def test_alef_and_taa_marbuta_folding():
    mod = Moderator(["اهبله"])
    assert not mod.is_clean("أهبلة")


def test_case_insensitive_latin():
    assert not Moderator(["badword"]).is_clean("BadWord!!")


def test_bad_name_gets_placeholder():
    assert Moderator(["badword"]).clean_name("xx badword", "123456789") == "Player6789"


def test_empty_name_gets_placeholder():
    assert Moderator([]).clean_name("​ ", "42") == "Player42"


def test_long_name_is_cut():
    assert len(Moderator([]).clean_name("a" * 50, "1")) == MAX_NAME_LEN


def test_banned_text_returns_none():
    mod = Moderator(["badword"])
    assert mod.clean_text("hi badword") is None
    assert mod.clean_text("hello") == "hello"


def test_from_file_skips_comments(tmp_path):
    path = tmp_path / "words.txt"
    path.write_text("# header\nbadword\n\n", encoding="utf-8")
    mod = Moderator.from_file(path)
    assert not mod.is_clean("badword")
    assert mod.is_clean("header")


def test_missing_file_means_no_filter(tmp_path):
    assert Moderator.from_file(tmp_path / "nope.txt").is_clean("anything")
