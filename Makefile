TARGET = snake
SRC = snake.asm
OBJ = $(SRC:.asm=.o)

all: $(TARGET)

$(TARGET): $(OBJ)
	ld -o $@ $^

%.o: %.asm
	nasm -f elf64 $< -o $@

run: all
	./$(TARGET)

clean:
	rm -f $(OBJ) $(TARGET)
